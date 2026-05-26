#Include "Protheus.ch"
#Include "TopConn.ch"
#Include "RESTFUL.ch"

/*/{Protheus.doc} WSPAINELCP
    REST API - Painel de Compras (PC + SC) filtrado por aprovador.
    Cada aprovador so enxerga os documentos da sua cadeia de aprovacao.

    GET /rest03/WSPAINELCP?apr=USERID&token=HASH

    Token: MD5("CICLO2026PAINEL#CP#" + apr)  -> U_CMAPTkCP(cApr)

    Retorna:
      pc_aberto    - Pedidos de Compra pendentes de aprovacao (do aprovador)
      sc_aberto    - Solicitacoes de Compra pendentes (do aprovador)
      pc_aprovado  - Pedidos de Compra aprovados/rejeitados (ultimos 60 dias)
      sc_aprovado  - Solicitacoes aprovadas/rejeitadas (ultimos 60 dias)

    Cadeia de filtro (igual ao WSAPROVINBOX):
      PC: SC7.C7_USER -> SY1.Y1_GRAPROV -> SAL.AL_APROV -> SAK.AK_USER = apr
      SC: SC1.C1_USER -> SY1.Y1_GRAPROV -> SAL.AL_APROV -> SAK.AK_USER = apr

    @type  WSRESTFUL
    @author Antonio
    @since 26/05/2026
/*/

WSRESTFUL WSPAINELCP DESCRIPTION "Painel de Compras - PC e SC filtrado por aprovador"

    WSDATA apr   AS STRING
    WSDATA token AS STRING

    WSMETHOD GET DESCRIPTION "Retorna PC e SC do aprovador agrupados por status" WSSYNTAX "/WSPAINELCP?apr={apr}&token={token}"

END WSRESTFUL

WSMETHOD GET WSRECEIVE apr, token WSSERVICE WSPAINELCP

    Local cApr      := AllTrim(::apr)
    Local cToken    := AllTrim(::token)
    Local cTokenEsp := ""
    Local cNomeApr  := ""
    Local cJson     := ""

    ::SetContentType("application/json")
    ::SetHeader("Access-Control-Allow-Origin",  "*")
    ::SetHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
    ::SetHeader("Access-Control-Allow-Headers", "Authorization, Content-Type")

    If Empty(cApr) .Or. Empty(cToken)
        ::SetResponse('{"erro":"Parametros apr e token sao obrigatorios"}')
        Return .T.
    EndIf

    cTokenEsp := U_CMAPTkCP(cApr)
    If cToken != cTokenEsp
        ConOut("[WSPAINELCP] Token invalido apr=" + cApr)
        ::SetResponse('{"erro":"Token invalido ou sem permissao"}')
        Return .T.
    EndIf

    fNomeAprovPainel(cApr, @cNomeApr)
    cJson := fMontaJsonPainel(cApr, cNomeApr)

    ConOut("[WSPAINELCP] Painel gerado - apr=" + cApr + " (" + cNomeApr + ")")
    ::SetResponse(cJson)
Return .T.

//-------------------------------------------------------------------
Static Function fNomeAprovPainel(cApr, cNome)
    Local cQry := ""
    Local cAli := GetNextAlias()

    Default cNome := ""

    cQry := " SELECT TOP 1 USR_NOME FROM SYS_USR WHERE USR_ID = '" + cApr + "' AND D_E_L_E_T_ = ' ' "
    cQry := ChangeQuery(cQry)

    If Select(cAli) > 0
        (cAli)->(dbCloseArea())
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAli, .T., .T.)
    If !(cAli)->(Eof())
        cNome := AllTrim((cAli)->USR_NOME)
    EndIf
    (cAli)->(dbCloseArea())
Return

//-------------------------------------------------------------------
Static Function fMontaJsonPainel(cApr, cNomeApr)
    Local cJson    := ""
    Local aPC_Ab   := {}
    Local aSC_Ab   := {}
    Local aPC_Ap   := {}
    Local aSC_Ap   := {}
    Local cDtCorte := DToS(Date() - 60)

    fBuscaPC(cApr, aPC_Ab, aPC_Ap, cDtCorte)
    fBuscaSC(cApr, aSC_Ab, aSC_Ap, cDtCorte)

    cJson := '{'
    cJson += '"apr":"'        + fPCEsc(cApr)     + '",'
    cJson += '"nome_apr":"'   + fPCEsc(cNomeApr) + '",'
    cJson += '"pc_aberto":'   + fArrayParaJson(aPC_Ab) + ','
    cJson += '"sc_aberto":'   + fArrayParaJson(aSC_Ab) + ','
    cJson += '"pc_aprovado":' + fArrayParaJson(aPC_Ap) + ','
    cJson += '"sc_aprovado":' + fArrayParaJson(aSC_Ap)
    cJson += '}'
Return cJson

//-------------------------------------------------------------------
// Busca Pedidos de Compra (SC7) - filtrado pela cadeia do aprovador
//-------------------------------------------------------------------
Static Function fBuscaPC(cApr, aAberto, aAprovado, cDtCorte)
    Local cQry     := ""
    Local cAli     := GetNextAlias()
    Local aRec     := {}
    Local cFil     := ""
    Local cNum     := ""
    Local cStatus  := ""
    Local cUrlBase := U_CMAPUrlBase()

    Default aAberto   := {}
    Default aAprovado := {}

    cQry  = " SELECT "
    cQry += "   RTRIM(SC7.C7_FILIAL)                          AS C7_FILIAL, "
    cQry += "   RTRIM(SC7.C7_NUM)                             AS C7_NUM, "
    cQry += "   MIN(SC7.C7_EMISSAO)                           AS C7_EMISSAO, "
    cQry += "   MAX(RTRIM(ISNULL(SC7.C7_USER, '')))           AS C7_USER, "
    cQry += "   MAX(RTRIM(ISNULL(SC7.C7_FORNECE, '')))        AS C7_FORNECE, "
    cQry += "   MAX(RTRIM(ISNULL(SC7.C7_LOJA, '')))           AS C7_LOJA, "
    cQry += "   MAX(RTRIM(ISNULL(SC7.C7_JUSTIFI, '')))        AS C7_JUSTIFI, "
    cQry += "   SUM(ISNULL(SC7.C7_TOTAL, 0))                  AS VALOR_TOTAL, "
    cQry += "   MAX(RTRIM(ISNULL(SA2.A2_NOME, '')))           AS A2_NOME, "
    cQry += "   MAX(RTRIM(ISNULL(SY1.Y1_NOME, '')))           AS Y1_NOME, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC7.C7_CONAPRO,'')) NOT IN ('L','R') THEN 1 ELSE 0 END) AS NPEND, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC7.C7_CONAPRO,'')) = 'L'            THEN 1 ELSE 0 END) AS NAPROV, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC7.C7_CONAPRO,'')) = 'R'            THEN 1 ELSE 0 END) AS NREJ "
    cQry += " FROM " + RetSQLName("SC7") + " SC7 "
    // Cadeia do aprovador: comprador -> grupo aprovacao -> aprovador
    cQry += " INNER JOIN " + RetSQLName("SY1") + " SY1 "
    cQry += "   ON SY1.Y1_USER = SC7.C7_USER AND SY1.D_E_L_E_T_ = ' ' "
    cQry += " INNER JOIN " + RetSQLName("SAL") + " SAL "
    cQry += "   ON SAL.AL_COD = SY1.Y1_GRAPROV AND SAL.D_E_L_E_T_ = ' ' "
    cQry += " INNER JOIN " + RetSQLName("SAK") + " SAK "
    cQry += "   ON SAK.AK_FILIAL = SAL.AL_FILIAL AND SAK.AK_COD = SAL.AL_APROV "
    cQry += "   AND SAK.AK_USER = '" + cApr + "' AND SAK.D_E_L_E_T_ = ' ' "
    // Fornecedor (opcional)
    cQry += " LEFT JOIN " + RetSQLName("SA2") + " A2 "
    cQry += "   ON A2.A2_COD = SC7.C7_FORNECE AND A2.A2_LOJA = SC7.C7_LOJA "
    cQry += "   AND A2.D_E_L_E_T_ = ' ' "
    cQry += " WHERE SC7.D_E_L_E_T_ = ' ' "
    cQry += "   AND SC7.C7_EMISSAO >= '" + cDtCorte + "' "
    cQry += " GROUP BY SC7.C7_FILIAL, SC7.C7_NUM "
    cQry += " ORDER BY MIN(SC7.C7_EMISSAO) DESC "

    cQry := ChangeQuery(cQry)

    If Select(cAli) > 0
        (cAli)->(dbCloseArea())
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAli, .T., .T.)

    While !(cAli)->(Eof())
        cFil   := AllTrim((cAli)->C7_FILIAL)
        cNum   := AllTrim((cAli)->C7_NUM)

        If (cAli)->NPEND > 0
            cStatus := "A"
        ElseIf (cAli)->NREJ > 0
            cStatus := "R"
        Else
            cStatus := "L"
        EndIf

        aRec := {}
        AAdd(aRec, "PC")
        AAdd(aRec, cNum)
        AAdd(aRec, cFil)
        AAdd(aRec, fPCEsc(AllTrim((cAli)->Y1_NOME)))       // comprador
        AAdd(aRec, fPCEsc(AllTrim((cAli)->A2_NOME)))       // fornecedor
        AAdd(aRec, fPCEsc(AllTrim((cAli)->C7_JUSTIFI)))    // justificativa
        AAdd(aRec, (cAli)->VALOR_TOTAL)
        AAdd(aRec, fPCFmtData((cAli)->C7_EMISSAO))
        AAdd(aRec, cStatus)
        AAdd(aRec, (cAli)->NPEND)
        AAdd(aRec, (cAli)->NAPROV)
        AAdd(aRec, (cAli)->NREJ)
        AAdd(aRec, cUrlBase + "/painel-pc.html?pc=" + cNum + "&fil=" + cFil + "&token=" + U_CMAGTkPC(cNum, cFil))
        AAdd(aRec, U_GeraTokenPC(cNum, "ALL", "A", cFil))
        AAdd(aRec, U_GeraTokenPC(cNum, "ALL", "R", cFil))

        If cStatus == "A"
            AAdd(aAberto, aRec)
        Else
            AAdd(aAprovado, aRec)
        EndIf

        (cAli)->(dbSkip())
    EndDo

    (cAli)->(dbCloseArea())
Return

//-------------------------------------------------------------------
// Busca Solicitacoes de Compra (SC1) - filtrado pela cadeia do aprovador
//-------------------------------------------------------------------
Static Function fBuscaSC(cApr, aAberto, aAprovado, cDtCorte)
    Local cQry     := ""
    Local cAli     := GetNextAlias()
    Local aRec     := {}
    Local cFil     := ""
    Local cNum     := ""
    Local cStatus  := ""
    Local cUrlBase := U_CMAPUrlBase()

    Default aAberto   := {}
    Default aAprovado := {}

    cQry  = " SELECT "
    cQry += "   RTRIM(SC1.C1_FILIAL)                          AS C1_FILIAL, "
    cQry += "   RTRIM(SC1.C1_NUM)                             AS C1_NUM, "
    cQry += "   MIN(SC1.C1_EMISSAO)                           AS C1_EMISSAO, "
    cQry += "   MAX(RTRIM(ISNULL(SC1.C1_SOLICIT, '')))        AS C1_SOLICIT, "
    cQry += "   MAX(RTRIM(ISNULL(SC1.C1_OBS, '')))            AS C1_OBS, "
    cQry += "   MAX(RTRIM(ISNULL(SC1.C1_FORNECE, '')))        AS C1_FORNECE, "
    cQry += "   MAX(RTRIM(ISNULL(SC1.C1_LOJA, '')))           AS C1_LOJA, "
    cQry += "   SUM(ISNULL(SC1.C1_QUANT * SC1.C1_PRECO, 0))  AS VALOR_EST, "
    cQry += "   MAX(RTRIM(ISNULL(SA2.A2_NOME, '')))           AS A2_NOME, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC1.C1_APROV,'')) NOT IN ('L','R') THEN 1 ELSE 0 END) AS NPEND, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC1.C1_APROV,'')) = 'L'            THEN 1 ELSE 0 END) AS NAPROV, "
    cQry += "   SUM(CASE WHEN RTRIM(ISNULL(SC1.C1_APROV,'')) = 'R'            THEN 1 ELSE 0 END) AS NREJ "
    cQry += " FROM " + RetSQLName("SC1") + " SC1 "
    // Cadeia do aprovador: solicitante -> grupo aprovacao -> aprovador
    cQry += " INNER JOIN " + RetSQLName("SY1") + " SY1 "
    cQry += "   ON SY1.Y1_USER = SC1.C1_USER AND SY1.D_E_L_E_T_ = ' ' "
    cQry += " INNER JOIN " + RetSQLName("SAL") + " SAL "
    cQry += "   ON SAL.AL_COD = SY1.Y1_GRAPROV AND SAL.D_E_L_E_T_ = ' ' "
    cQry += " INNER JOIN " + RetSQLName("SAK") + " SAK "
    cQry += "   ON SAK.AK_FILIAL = SAL.AL_FILIAL AND SAK.AK_COD = SAL.AL_APROV "
    cQry += "   AND SAK.AK_USER = '" + cApr + "' AND SAK.D_E_L_E_T_ = ' ' "
    // Fornecedor (opcional)
    cQry += " LEFT JOIN " + RetSQLName("SA2") + " A2 "
    cQry += "   ON A2.A2_COD = SC1.C1_FORNECE AND A2.A2_LOJA = SC1.C1_LOJA "
    cQry += "   AND A2.D_E_L_E_T_ = ' ' "
    cQry += " WHERE SC1.D_E_L_E_T_ = ' ' "
    cQry += "   AND SC1.C1_EMISSAO >= '" + cDtCorte + "' "
    cQry += " GROUP BY SC1.C1_FILIAL, SC1.C1_NUM "
    cQry += " ORDER BY MIN(SC1.C1_EMISSAO) DESC "

    cQry := ChangeQuery(cQry)

    If Select(cAli) > 0
        (cAli)->(dbCloseArea())
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAli, .T., .T.)

    While !(cAli)->(Eof())
        cFil   := AllTrim((cAli)->C1_FILIAL)
        cNum   := AllTrim((cAli)->C1_NUM)

        If (cAli)->NPEND > 0
            cStatus := "A"
        ElseIf (cAli)->NREJ > 0
            cStatus := "R"
        Else
            cStatus := "L"
        EndIf

        aRec := {}
        AAdd(aRec, "SC")
        AAdd(aRec, cNum)
        AAdd(aRec, cFil)
        AAdd(aRec, fPCEsc(AllTrim((cAli)->C1_SOLICIT)))    // solicitante
        AAdd(aRec, fPCEsc(AllTrim((cAli)->A2_NOME)))       // fornecedor
        AAdd(aRec, fPCEsc(AllTrim((cAli)->C1_OBS)))        // observacao/motivo
        AAdd(aRec, (cAli)->VALOR_EST)
        AAdd(aRec, fPCFmtData((cAli)->C1_EMISSAO))
        AAdd(aRec, cStatus)
        AAdd(aRec, (cAli)->NPEND)
        AAdd(aRec, (cAli)->NAPROV)
        AAdd(aRec, (cAli)->NREJ)
        AAdd(aRec, cUrlBase + "/painel-sc.html?sc=" + cNum + "&fil=" + cFil + "&token=" + U_CMAGTkSC(cNum, cFil))
        AAdd(aRec, MD5("CICLO2026SC#" + cFil + "#" + cNum + "#ALL#A"))
        AAdd(aRec, MD5("CICLO2026SC#" + cFil + "#" + cNum + "#ALL#R"))

        If cStatus == "A"
            AAdd(aAberto, aRec)
        Else
            AAdd(aAprovado, aRec)
        EndIf

        (cAli)->(dbSkip())
    EndDo

    (cAli)->(dbCloseArea())
Return

//-------------------------------------------------------------------
// Monta JSON de um array de documentos
// Cada elemento: [tipo,num,fil,responsavel,fornecedor,justif,valor,
//                 emissao,status,npend,naprov,nrej,url_detalhe,
//                 tk_aprov,tk_rejeit]
//-------------------------------------------------------------------
Static Function fArrayParaJson(aDocs)
    Local cJson    := "["
    Local nI       := 0
    Local aD       := {}
    Local cRest    := GetRestServerIp()
    Local nPort    := GetRestServerPort()
    Local cRestBase := "http://" + cRest + ":" + cValToChar(nPort) + "/rest03"

    For nI := 1 To Len(aDocs)
        aD := aDocs[nI]
        If nI > 1
            cJson += ","
        EndIf

        cJson += "{"
        cJson += '"tipo":"'           + aD[1]  + '",'
        cJson += '"num":"'            + aD[2]  + '",'
        cJson += '"fil":"'            + aD[3]  + '",'
        cJson += '"responsavel":"'    + aD[4]  + '",'
        cJson += '"fornecedor":"'     + aD[5]  + '",'
        cJson += '"justificativa":"'  + aD[6]  + '",'
        cJson += '"valor":'           + fPCNum(aD[7], 2) + ','
        cJson += '"emissao":"'        + aD[8]  + '",'
        cJson += '"status":"'         + aD[9]  + '",'
        cJson += '"n_pend":'          + cValToChar(aD[10]) + ','
        cJson += '"n_aprov":'         + cValToChar(aD[11]) + ','
        cJson += '"n_rej":'           + cValToChar(aD[12]) + ','
        cJson += '"url_detalhe":"'    + fPCEsc(aD[13]) + '",'

        If aD[1] == "PC"
            cJson += '"url_aprov":"'  + fPCEsc(cRestBase + "/WSAPROVPC?pc="  + aD[2] + "&item=ALL&acao=A&fil=" + aD[3] + "&token=" + aD[14]) + '",'
            cJson += '"url_rejeit":"' + fPCEsc(cRestBase + "/WSAPROVPC?pc="  + aD[2] + "&item=ALL&acao=R&fil=" + aD[3] + "&token=" + aD[15]) + '"'
        Else
            cJson += '"url_aprov":"'  + fPCEsc(cRestBase + "/WSAPROVSC?sc="  + aD[2] + "&item=ALL&acao=A&fil=" + aD[3] + "&token=" + aD[14]) + '",'
            cJson += '"url_rejeit":"' + fPCEsc(cRestBase + "/WSAPROVSC?sc="  + aD[2] + "&item=ALL&acao=R&fil=" + aD[3] + "&token=" + aD[15]) + '"'
        EndIf

        cJson += "}"
    Next nI

    cJson += "]"
Return cJson

//-------------------------------------------------------------------
Static Function fPCEsc(cVal)
    Default cVal := ""
    cVal := AllTrim(cVal)
    cVal := StrTran(cVal, '\',  '\\')
    cVal := StrTran(cVal, '"',  '\"')
    cVal := StrTran(cVal, Chr(13), '')
    cVal := StrTran(cVal, Chr(10), '\n')
Return cVal

Static Function fPCNum(nVal, nDec)
    Default nDec := 2
    If ValType(nVal) != "N"
        nVal := 0
    EndIf
Return StrTran(AllTrim(Str(nVal, 20, nDec)), ",", ".")

Static Function fPCFmtData(xData)
    Local cRet := ""
    Local cD   := ""
    If ValType(xData) == "D" .And. !Empty(xData)
        cRet := DToC(xData)
    ElseIf ValType(xData) == "C"
        cD := AllTrim(xData)
        If Len(cD) >= 8 .And. !("a" $ Lower(cD))
            cRet := SubStr(cD, 7, 2) + "/" + SubStr(cD, 5, 2) + "/" + SubStr(cD, 1, 4)
        Else
            cRet := cD
        EndIf
    EndIf
Return cRet
