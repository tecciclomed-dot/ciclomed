#Include "Protheus.ch"
#Include "TopConn.ch"
#Include "RESTFUL.ch"

/*/{Protheus.doc} WSSOLPV
    REST API - App Solicitacao de Pedido de Venda (vendedor externo).
    Fluxo scan-first: consulta serial (SBF/SB6) e gera PV.

    GET  ?acao=login&vendedor=&senha=
    GET  ?acao=serial&serial=&tipo=R|C|P|N|M&fil=&vendedor=
    GET  ?acao=produtos&q=              -> busca produto SB1 (tipo M)
    GET  ?acao=hospitais&q=&vendedor=
    GET  ?acao=pacientes&q=
    GET  ?acao=medicos&q=
    GET  ?acao=convenios&q=
    GET  ?acao=cirurgias&q=
    GET  ?acao=painel&fil=          -> painel logistica (SC5/SC6)
    GET  ?acao=versao
    POST { JSON } -> gera pedido via MATA410

    Tipo x Armazem esperado:
      R = Reserva          -> local 57 (P3 / poder de terceiros)
      C = Consignacao      -> local 50
      P = Consig. Permanente -> local 50
      N = Venda / Eletivo  -> local 50
      M = Solicitacao material -> local 50 (PV sem serial, reserva estoque)

    @type  WSRESTFUL
    @author Antonio
    @since  27/05/2026
/*/

WSRESTFUL WSSOLPV DESCRIPTION "App Solicitacao PV - Serial SBF/SB6 + Geracao Pedido"

    WSDATA acao     AS STRING
    WSDATA serial   AS STRING
    WSDATA tipo     AS STRING
    WSDATA fil      AS STRING
    WSDATA vendedor AS STRING
    WSDATA senha    AS STRING
    WSDATA q        AS STRING

    WSMETHOD GET  DESCRIPTION "Consultas (serial, login, autocomplete)" WSSYNTAX "/WSSOLPV?acao={acao}"
    WSMETHOD POST DESCRIPTION "Gerar pedido de venda"                   WSSYNTAX "/WSSOLPV {JSON body}"

END WSRESTFUL

WSMETHOD GET WSRECEIVE acao, serial, tipo, fil, vendedor, senha, q WSSERVICE WSSOLPV

    Local cAcao := Upper(AllTrim(::acao))
    Local cJson := ""

    ::SetContentType("application/json")
    ::SetHeader("Access-Control-Allow-Origin",  "*")
    ::SetHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    ::SetHeader("Access-Control-Allow-Headers", "Authorization, Content-Type")

    Do Case
        Case cAcao == "LOGIN"
            cJson := fSolLogin(AllTrim(::vendedor), AllTrim(::senha))

        Case cAcao == "SERIAL"
            cJson := fSolBuscaSerial(AllTrim(::serial), Upper(AllTrim(::tipo)), AllTrim(::fil), AllTrim(::vendedor))

        Case cAcao == "HOSPITAIS"
            cJson := fSolAutoComplete("HOSP", AllTrim(::q), AllTrim(::vendedor))

        Case cAcao == "PACIENTES"
            cJson := fSolAutoComplete("PAC", AllTrim(::q), "")

        Case cAcao == "MEDICOS"
            cJson := fSolAutoComplete("MED", AllTrim(::q), "")

        Case cAcao == "CONVENIOS"
            cJson := fSolAutoComplete("CONV", AllTrim(::q), "")

        Case cAcao == "CIRURGIAS"
            cJson := fSolAutoComplete("CIR", AllTrim(::q), "")

        Case cAcao == "PRODUTOS"
            cJson := fSolBuscaProd(AllTrim(::q))

        Case cAcao == "VERSAO"
            cJson := '{"ok":true,"servico":"WSSOLPV","versao":"1.0.3-material"}'

        Case cAcao == "PAINEL"
            cJson := fSolPainel(AllTrim(::fil))

        Otherwise
            cJson := '{"ok":false,"msg":"Acao invalida. Use: login, serial, produtos, painel, hospitais, pacientes, medicos, convenios, cirurgias"}'
    EndCase

    ::SetResponse(cJson)
Return .T.

WSMETHOD POST WSRECEIVE WSSERVICE WSSOLPV

    Local cBody  := ::GetContent()
    Local oJson  := JsonObject():New()
    Local cError := ""
    Local cJson  := ""

    ::SetContentType("application/json")
    ::SetHeader("Access-Control-Allow-Origin",  "*")
    ::SetHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    ::SetHeader("Access-Control-Allow-Headers", "Authorization, Content-Type")

    cError := oJson:FromJson(cBody)
    If !Empty(cError)
        ::SetResponse('{"ok":false,"msg":"JSON invalido"}')
        FreeObj(oJson)
        Return .T.
    EndIf

    cJson := fSolCriarPedido(oJson)
    ::SetResponse(cJson)
    FreeObj(oJson)
Return .T.

//=====================================================================
// Login vendedor (SA3)
//=====================================================================
Static Function fSolLogin(cVend, cSenha)

    Local cJson  := ""
    Local cQry   := ""
    Local cAlias := GetNextAlias()

    If Empty(cVend) .Or. Empty(cSenha)
        Return '{"ok":false,"msg":"Vendedor e senha obrigatorios"}'
    EndIf

    cQry := " SELECT RTRIM(A3.A3_COD) AS A3_COD, RTRIM(A3.A3_NOME) AS A3_NOME, "
    cQry += "        RTRIM(A3.A3_NREDUZ) AS A3_NREDUZ, RTRIM(A3.A3_EMAIL) AS A3_EMAIL "
    cQry += " FROM " + RetSqlName("SA3") + " A3 WITH (NOLOCK) "
    cQry += " WHERE A3.D_E_L_E_T_ = ' ' "
    cQry += "   AND A3.A3_COD = '" + fSolSqlEsc(PadR(cVend, TamSX3("A3_COD")[1])) + "' "
    cQry += "   AND A3.A3_SENHA = '" + fSolSqlEsc(PadR(cSenha, TamSX3("A3_SENHA")[1])) + "' "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    If (cAlias)->(Eof())
        (cAlias)->(dbCloseArea())
        Return '{"ok":false,"msg":"Vendedor ou senha invalidos"}'
    EndIf

    cJson := '{"ok":true,'
    cJson += '"vendedor":"' + fSolJsonEsc(AllTrim((cAlias)->A3_COD)) + '",'
    cJson += '"nome":"'     + fSolJsonEsc(AllTrim((cAlias)->A3_NOME)) + '",'
    cJson += '"nreduz":"'   + fSolJsonEsc(AllTrim((cAlias)->A3_NREDUZ)) + '",'
    cJson += '"email":"'    + fSolJsonEsc(AllTrim((cAlias)->A3_EMAIL)) + '"}'

    (cAlias)->(dbCloseArea())
Return cJson

//=====================================================================
// Busca produtos SB1 (Solicitacao de material - sem serial)
//=====================================================================
Static Function fSolBuscaProd(cQ)

    Local cJson   := ""
    Local cQry    := ""
    Local cAlias  := GetNextAlias()
    Local lFirst  := .T.
    Local aTokens := {}
    Local nI      := 0

    If Len(AllTrim(cQ)) < 2
        Return '{"ok":true,"itens":[]}'
    EndIf

    aTokens := fSolTokens(cQ)

    cQry := " SELECT TOP 20 RTRIM(B1.B1_COD) AS COD, RTRIM(B1.B1_DESC) AS DESCR, B1.B1_PRV1 AS PRECO "
    cQry += " FROM " + RetSqlName("SB1") + " B1 WITH (NOLOCK) "
    cQry += " WHERE B1.D_E_L_E_T_ = ' ' AND B1.B1_MSBLQL <> '1' "
    For nI := 1 To Len(aTokens)
        cQry += " AND (UPPER(B1.B1_COD) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
        cQry += "   OR UPPER(B1.B1_DESC) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%') "
    Next
    cQry += " ORDER BY B1.B1_DESC "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    cJson := '{"ok":true,"itens":['

    While !(cAlias)->(Eof())
        If !lFirst
            cJson += ','
        EndIf
        lFirst := .F.
        cJson += '{"codigo":"'   + fSolJsonEsc(AllTrim((cAlias)->COD)) + '",'
        cJson += '"descricao":"' + fSolJsonEsc(AllTrim((cAlias)->DESCR)) + '",'
        cJson += '"preco":'      + fSolJsonNum((cAlias)->PRECO) + '}'
        (cAlias)->(dbSkip())
    EndDo

    cJson += ']}'
    (cAlias)->(dbCloseArea())
Return cJson

Static Function fSolPrecoProd(cCli, cLoja, cProd)

    Local nPreco := 0
    Local aArea  := GetArea()

    Default cCli  := ""
    Default cLoja := ""
    Default cProd := ""

    DbSelectArea("SB1")
    SB1->(DbSetOrder(1))
    If SB1->(DbSeek(xFilial("SB1") + PadR(cProd, TamSX3("B1_COD")[1])))
        nPreco := SB1->B1_PRV1
    EndIf

    RestArea(aArea)
Return nPreco

//=====================================================================
// Armazem esperado por tipo de pedido
//=====================================================================
Static Function fSolArmEsperado(cTipo)
    If cTipo == "R"
        Return "57"
    EndIf
Return "50"

Static Function fSolPrefixoPV(cTipo)
    Do Case
        Case cTipo == "R"
            Return "R"
        Case cTipo == "C"
            Return "C"
        Case cTipo == "P"
            Return "P"
        Case cTipo == "M"
            Return "M"
        Otherwise
            Return "N"
    EndCase
Return "N"

//=====================================================================
// Busca serial - SBF (saldo) + fallback SB6 (P3) para Reserva
//=====================================================================
Static Function fSolBuscaSerial(cSerial, cTipo, cFil, cVend)

    Local cJson     := ""
    Local cArmEsp   := fSolArmEsperado(cTipo)
    Local cQry      := ""
    Local cAlias    := GetNextAlias()
    Local lAchou    := .F.
    Local cArm      := ""
    Local cProd     := ""
    Local cDesc     := ""
    Local cLote     := ""
    Local cVal      := ""
    Local cCliFor   := ""
    Local cLoja     := ""
    Local cNomCli   := ""
    Local cCidade   := ""
    Local cFilSbf   := ""
    Local cPedAtivo := ""
    Local nPreco    := 0
    Local cAviso    := ""
    Local cOrigem   := "SBF"

    ConOut("[WSSOLPV] serial=" + cSerial + " tipo=" + cTipo + " fil=" + cFil + " vend=" + cVend)

    If Empty(cSerial)
        Return '{"ok":false,"msg":"Parametro serial obrigatorio"}'
    EndIf

    If !cTipo $ "R,C,P,N"
        Return '{"ok":false,"msg":"Tipo invalido. Use R, C, P ou N"}'
    EndIf

    // --- 1) Busca na SBF (ChkItemPV - saldo por serial) ---
    cQry := " SELECT TOP 1 "
    cQry += "   RTRIM(SBF.BF_FILIAL)  AS BF_FILIAL, "
    cQry += "   RTRIM(SBF.BF_PRODUTO) AS PRODUTO, "
    cQry += "   RTRIM(SBF.BF_NUMSERI) AS NUMSERI, "
    cQry += "   RTRIM(SBF.BF_LOCAL)   AS ARMAZ, "
    cQry += "   RTRIM(SBF.BF_LOTECTL) AS LOTE, "
    cQry += "   SBF.BF_DATAVEN        AS VALIDADE, "
    cQry += "   RTRIM(B1.B1_DESC)     AS DESC_PROD, "
    cQry += "   COALESCE(SDB_ENT.DB_CLIFOR, '') AS CLIFOR, "
    cQry += "   COALESCE(SDB_ENT.DB_LOJA, '')   AS LOJA, "
    cQry += "   COALESCE(RTRIM(A1.A1_NOME), '') AS NOME_CLI, "
    cQry += "   COALESCE(RTRIM(A1.A1_MUN), '')  AS CIDADE, "
    cQry += "   COALESCE(RTRIM(A1.A1_EST), '')  AS UF, "
    cQry += "   COALESCE(ULT_SD2.D2_PRCVEN, 0)  AS PRECO, "
    cQry += "   COALESCE(RTRIM(ULT_PED.C6_NUM), '') AS PEDIDO "
    cQry += " FROM " + RetSqlName("SBF") + " SBF WITH (NOLOCK) "
    cQry += " INNER JOIN " + RetSqlName("SB1") + " B1 WITH (NOLOCK) "
    cQry += "   ON B1.D_E_L_E_T_ = ' ' AND B1.B1_COD = SBF.BF_PRODUTO "
    cQry += " OUTER APPLY ( "
    cQry += "   SELECT TOP 1 DB_CLIFOR, DB_LOJA "
    cQry += "   FROM " + RetSqlName("SDB") + " WITH (NOLOCK) "
    cQry += "   WHERE D_E_L_E_T_ = ' ' AND DB_ESTORNO <> 'S' "
    cQry += "     AND RTRIM(DB_NUMSERI) = RTRIM(SBF.BF_NUMSERI) "
    cQry += "     AND DB_ORIGEM = 'SD1' "
    cQry += "   ORDER BY DB_DATA DESC "
    cQry += " ) SDB_ENT "
    cQry += " LEFT JOIN " + RetSqlName("SA1") + " A1 WITH (NOLOCK) "
    cQry += "   ON A1.D_E_L_E_T_ = ' ' AND A1.A1_COD = SDB_ENT.DB_CLIFOR AND A1.A1_LOJA = SDB_ENT.DB_LOJA "
    cQry += " OUTER APPLY ( "
    cQry += "   SELECT TOP 1 D2_PRCVEN "
    cQry += "   FROM " + RetSqlName("SD2") + " WITH (NOLOCK) "
    cQry += "   WHERE D_E_L_E_T_ = ' ' AND D2_NUMSERI = SBF.BF_NUMSERI "
    cQry += "   ORDER BY D2_EMISSAO DESC "
    cQry += " ) ULT_SD2 "
    cQry += " OUTER APPLY ( "
    cQry += "   SELECT TOP 1 C6_NUM "
    cQry += "   FROM " + RetSqlName("SC6") + " WITH (NOLOCK) "
    cQry += "   WHERE D_E_L_E_T_ = ' ' AND C6_NUMSERI = SBF.BF_NUMSERI AND C6_QTDENT = 0 "
    cQry += " ) ULT_PED "
    cQry += " WHERE SBF.D_E_L_E_T_ = ' ' "
    cQry += "   AND SBF.BF_QUANT > 0 "
    cQry += "   AND RTRIM(SBF.BF_NUMSERI) = '" + fSolSqlEsc(cSerial) + "' "
    If !Empty(cFil)
        cQry += "   AND RTRIM(SBF.BF_FILIAL) = '" + fSolSqlEsc(PadR(cFil, TamSX3("BF_FILIAL")[1])) + "' "
    EndIf
    cQry += " ORDER BY CASE WHEN RTRIM(SBF.BF_LOCAL) = '" + cArmEsp + "' THEN 0 ELSE 1 END, SBF.R_E_C_N_O_ ASC "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    If !(cAlias)->(Eof())
        lAchou    := .T.
        cOrigem   := "SBF"
        cFilSbf   := AllTrim((cAlias)->BF_FILIAL)
        cProd     := AllTrim((cAlias)->PRODUTO)
        cDesc     := AllTrim((cAlias)->DESC_PROD)
        cLote     := AllTrim((cAlias)->LOTE)
        cVal      := AllTrim((cAlias)->VALIDADE)
        cArm      := AllTrim((cAlias)->ARMAZ)
        cCliFor   := AllTrim((cAlias)->CLIFOR)
        cLoja     := AllTrim((cAlias)->LOJA)
        cNomCli   := AllTrim((cAlias)->NOME_CLI)
        cCidade   := AllTrim((cAlias)->CIDADE)
        If !Empty(AllTrim((cAlias)->UF))
            cCidade += "/" + AllTrim((cAlias)->UF)
        EndIf
        nPreco    := (cAlias)->PRECO
        cPedAtivo := AllTrim((cAlias)->PEDIDO)
    EndIf

    (cAlias)->(dbCloseArea())

    // --- 2) Fallback SB6 (P3) somente para Reserva ---
    If !lAchou .And. cTipo == "R"
        cJson := fSolSerSB6(cSerial, cFil, @cProd, @cDesc, @cLote, @cVal, @cArm, @cCliFor, @cLoja, @cNomCli, @cCidade, @cFilSbf, @nPreco, @cPedAtivo)
        If Left(cJson, 8) == '{"ok":fa'
            Return cJson
        EndIf
        If !Empty(cProd)
            lAchou  := .T.
            cOrigem := "SB6"
        EndIf
    EndIf

    If !lAchou
        Return '{"ok":false,"msg":"Serial nao encontrado com saldo disponivel (SBF/SB6)"}'
    EndIf

    // Serial ja em outro pedido aberto
    If !Empty(cPedAtivo) .And. AllTrim(cPedAtivo) <> ""
        Return '{"ok":false,"msg":"Serial ja vinculado ao pedido ' + fSolJsonEsc(cPedAtivo) + '"}'
    EndIf

    // Local diferente do esperado -> aviso (app ainda pode exibir)
    If AllTrim(cArm) <> cArmEsp
        cAviso := "Serial localizado no armazem " + AllTrim(cArm) + ", esperado " + cArmEsp + " para tipo " + cTipo + "."
    EndIf

    // Reserva: se local 57 e sem cliente na SBF, busca cliente na SB6
    If cTipo == "R" .And. cArm == "57" .And. Empty(cCliFor)
        fSolClienteSB6(cSerial, cProd, cFilSbf, @cCliFor, @cLoja, @cNomCli, @cCidade)
    EndIf

    cJson := fSolMontaJsonSerial(cSerial, cTipo, cOrigem, cProd, cDesc, cLote, cVal, cArm, cArmEsp, cFilSbf, nPreco, cCliFor, cLoja, cNomCli, cCidade, cAviso)
Return cJson

// Nome curto (10 chars AdvPL) - evita colisao com fSolBuscaSerial -> fSolBuscaS
Static Function fSolSerSB6(cSerial, cFil, cProd, cDesc, cLote, cVal, cArm, cCliFor, cLoja, cNomCli, cCidade, cFilB6, nPreco, cPedAtivo)

    Local cQry   := ""
    Local cAlias := GetNextAlias()
    Local cJson  := ""

    cQry := " SELECT TOP 1 "
    cQry += "   RTRIM(B6.B6_FILIAL)  AS FILIAL, "
    cQry += "   RTRIM(B6.B6_PRODUTO) AS PRODUTO, "
    cQry += "   RTRIM(B1.B1_DESC)    AS DESC_PROD, "
    cQry += "   RTRIM(D2.D2_LOTECTL) AS LOTE, "
    cQry += "   RTRIM(B8.B8_DTVALID) AS VALIDADE, "
    cQry += "   RTRIM(B6.B6_LOCAL)   AS ARMAZ, "
    cQry += "   RTRIM(B6.B6_CLIFOR)  AS CLIFOR, "
    cQry += "   RTRIM(B6.B6_LOJA)    AS LOJA, "
    cQry += "   RTRIM(A1.A1_NOME)    AS NOME_CLI, "
    cQry += "   RTRIM(A1.A1_MUN)     AS CIDADE, "
    cQry += "   RTRIM(A1.A1_EST)     AS UF, "
    cQry += "   B6.B6_PRUNIT         AS PRECO, "
    cQry += "   COALESCE(RTRIM(C6.C6_NUM), '') AS PEDIDO "
    cQry += " FROM " + RetSqlName("SB6") + " B6 WITH (NOLOCK) "
    cQry += " INNER JOIN " + RetSqlName("SD2") + " D2 WITH (NOLOCK) "
    cQry += "   ON D2.D_E_L_E_T_ = ' ' AND D2.D2_IDENTB6 = B6.B6_IDENT "
    cQry += "   AND D2.D2_FILIAL = B6.B6_FILIAL AND RTRIM(D2.D2_NUMSERI) = '" + fSolSqlEsc(cSerial) + "' "
    cQry += " INNER JOIN " + RetSqlName("SB1") + " B1 WITH (NOLOCK) "
    cQry += "   ON B1.D_E_L_E_T_ = ' ' AND B1.B1_COD = B6.B6_PRODUTO "
    cQry += " LEFT JOIN " + RetSqlName("SA1") + " A1 WITH (NOLOCK) "
    cQry += "   ON A1.D_E_L_E_T_ = ' ' AND A1.A1_COD = B6.B6_CLIFOR AND A1.A1_LOJA = B6.B6_LOJA "
    cQry += " LEFT JOIN " + RetSqlName("SB8") + " B8 WITH (NOLOCK) "
    cQry += "   ON B8.D_E_L_E_T_ = ' ' AND B8.B8_PRODUTO = B6.B6_PRODUTO "
    cQry += "   AND B8.B8_LOTECTL = D2.D2_LOTECTL AND B8.B8_LOCAL = B6.B6_LOCAL "
    cQry += "   AND B8.B8_FILIAL = B6.B6_FILIAL "
    cQry += " LEFT JOIN " + RetSqlName("SC6") + " C6 WITH (NOLOCK) "
    cQry += "   ON C6.D_E_L_E_T_ = ' ' AND C6.C6_NUMSERI = D2.D2_NUMSERI AND C6.C6_QTDENT = 0 "
    cQry += " WHERE B6.D_E_L_E_T_ = ' ' "
    cQry += "   AND B6.B6_PODER3 = 'R' AND B6.B6_SALDO > 0 "
    If !Empty(cFil)
        cQry += "   AND RTRIM(B6.B6_FILIAL) = '" + fSolSqlEsc(PadR(cFil, TamSX3("B6_FILIAL")[1])) + "' "
    EndIf
    cQry += " ORDER BY B6.B6_EMISSAO DESC "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    If (cAlias)->(Eof())
        (cAlias)->(dbCloseArea())
        Return '{"ok":false,"msg":"Serial nao encontrado em Poder de Terceiros (SB6)"}'
    EndIf

    cFilB6    := AllTrim((cAlias)->FILIAL)
    cProd     := AllTrim((cAlias)->PRODUTO)
    cDesc     := AllTrim((cAlias)->DESC_PROD)
    cLote     := AllTrim((cAlias)->LOTE)
    cVal      := AllTrim((cAlias)->VALIDADE)
    cArm      := "57"
    cCliFor   := AllTrim((cAlias)->CLIFOR)
    cLoja     := AllTrim((cAlias)->LOJA)
    cNomCli   := AllTrim((cAlias)->NOME_CLI)
    cCidade   := AllTrim((cAlias)->CIDADE)
    If !Empty(AllTrim((cAlias)->UF))
        cCidade += "/" + AllTrim((cAlias)->UF)
    EndIf
    nPreco    := (cAlias)->PRECO
    cPedAtivo := AllTrim((cAlias)->PEDIDO)

    (cAlias)->(dbCloseArea())
Return ""

Static Function fSolClienteSB6(cSerial, cProd, cFil, cCliFor, cLoja, cNomCli, cCidade)

    Local cQry   := ""
    Local cAlias := GetNextAlias()

    Default cFil := ""

    cQry := " SELECT TOP 1 "
    cQry += "   RTRIM(B6.B6_CLIFOR) AS CLIFOR, "
    cQry += "   RTRIM(B6.B6_LOJA)   AS LOJA, "
    cQry += "   RTRIM(A1.A1_NOME)   AS NOME_CLI, "
    cQry += "   RTRIM(A1.A1_MUN)    AS CIDADE, "
    cQry += "   RTRIM(A1.A1_EST)    AS UF "
    cQry += " FROM " + RetSqlName("SB6") + " B6 WITH (NOLOCK) "
    cQry += " INNER JOIN " + RetSqlName("SD2") + " D2 WITH (NOLOCK) "
    cQry += "   ON D2.D_E_L_E_T_ = ' ' AND D2.D2_IDENTB6 = B6.B6_IDENT "
    cQry += "   AND D2.D2_FILIAL = B6.B6_FILIAL AND RTRIM(D2.D2_NUMSERI) = '" + fSolSqlEsc(cSerial) + "' "
    cQry += " LEFT JOIN " + RetSqlName("SA1") + " A1 WITH (NOLOCK) "
    cQry += "   ON A1.D_E_L_E_T_ = ' ' AND A1.A1_COD = B6.B6_CLIFOR AND A1.A1_LOJA = B6.B6_LOJA "
    cQry += " WHERE B6.D_E_L_E_T_ = ' ' AND B6.B6_PODER3 = 'R' AND B6.B6_SALDO > 0 "
    If !Empty(cProd)
        cQry += "   AND B6.B6_PRODUTO = '" + fSolSqlEsc(cProd) + "' "
    EndIf
    If !Empty(cFil)
        cQry += "   AND RTRIM(B6.B6_FILIAL) = '" + fSolSqlEsc(PadR(cFil, TamSX3("B6_FILIAL")[1])) + "' "
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    If !(cAlias)->(Eof())
        cCliFor := AllTrim((cAlias)->CLIFOR)
        cLoja   := AllTrim((cAlias)->LOJA)
        cNomCli := AllTrim((cAlias)->NOME_CLI)
        cCidade := AllTrim((cAlias)->CIDADE)
        If !Empty(AllTrim((cAlias)->UF))
            cCidade += "/" + AllTrim((cAlias)->UF)
        EndIf
    EndIf

    (cAlias)->(dbCloseArea())
Return

Static Function fSolMontaJsonSerial(cSerial, cTipo, cOrigem, cProd, cDesc, cLote, cVal, cArm, cArmEsp, cFil, nPreco, cCliFor, cLoja, cNomCli, cCidade, cAviso)

    Local cJson := ""
    Local lTemCli := !Empty(cCliFor)

    cJson := '{"ok":true,'
    cJson += '"serial":"'       + fSolJsonEsc(cSerial) + '",'
    cJson += '"tipo":"'          + fSolJsonEsc(cTipo) + '",'
    cJson += '"origem":"'        + fSolJsonEsc(cOrigem) + '",'
    cJson += '"produto":"'       + fSolJsonEsc(cProd) + '",'
    cJson += '"descricao":"'     + fSolJsonEsc(cDesc) + '",'
    cJson += '"lote":"'          + fSolJsonEsc(cLote) + '",'
    cJson += '"validade":"'      + fSolJsonEsc(cVal) + '",'
    cJson += '"validadeFmt":"'   + fSolJsonEsc(fSolFmtData(cVal)) + '",'
    cJson += '"local":"'         + fSolJsonEsc(cArm) + '",'
    cJson += '"localEsperado":"' + fSolJsonEsc(cArmEsp) + '",'
    cJson += '"filial":"'        + fSolJsonEsc(cFil) + '",'
    cJson += '"preco":'          + fSolJsonNum(nPreco) + ','

    If lTemCli
        cJson += '"cliente":{"id":"'   + fSolJsonEsc(cCliFor) + '",'
        cJson += '"loja":"'            + fSolJsonEsc(cLoja) + '",'
        cJson += '"nome":"'            + fSolJsonEsc(cNomCli) + '",'
        cJson += '"cidade":"'          + fSolJsonEsc(cCidade) + '"},'
    Else
        cJson += '"cliente":null,'
    EndIf

    cJson += '"aviso":"' + fSolJsonEsc(cAviso) + '"}'
Return cJson

//=====================================================================
// Autocomplete (hospitais=SA1, demais=historico SC5)
//=====================================================================
Static Function fSolAutoComplete(cTipoAuto, cQ, cVend)

    Local cJson   := ""
    Local cQry    := ""
    Local cAlias  := GetNextAlias()
    Local lFirst  := .T.
    Local cLike   := ""
    Local aTokens := {}
    Local nI      := 0
    Local cCampo  := ""
    Local cInfo   := ""

    If Len(AllTrim(cQ)) < 2
        Return '{"ok":true,"itens":[]}'
    EndIf

    aTokens := fSolTokens(cQ)

    Do Case
        Case cTipoAuto == "HOSP"
            cCampo := "A1_NOME"
            cInfo  := "CNPJ"
            cQry := " SELECT TOP 20 RTRIM(A1.A1_COD) AS ID, RTRIM(A1.A1_LOJA) AS LOJA, RTRIM(A1.A1_NOME) AS NOME, "
            cQry += "        RTRIM(A1.A1_CGC) AS INFO1, RTRIM(A1.A1_MUN) AS INFO2, RTRIM(A1.A1_EST) AS INFO3 "
            cQry += " FROM " + RetSqlName("SA1") + " A1 WITH (NOLOCK) "
            cQry += " WHERE A1.D_E_L_E_T_ = ' ' AND A1.A1_MSBLQL <> '1' "
            For nI := 1 To Len(aTokens)
                cQry += " AND UPPER(A1.A1_NOME) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
            Next
            cQry += " ORDER BY A1.A1_NOME "

        Case cTipoAuto == "PAC"
            cCampo := "C5_PACIENT"
            cQry := " SELECT TOP 20 RTRIM(C5.C5_PACIENT) AS NOME, '' AS ID, '' AS INFO1, '' AS INFO2, '' AS INFO3 "
            cQry += " FROM " + RetSqlName("SC5") + " C5 WITH (NOLOCK) "
            cQry += " WHERE C5.D_E_L_E_T_ = ' ' AND RTRIM(ISNULL(C5.C5_PACIENT,'')) <> '' "
            For nI := 1 To Len(aTokens)
                cQry += " AND UPPER(C5.C5_PACIENT) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
            Next
            cQry += " GROUP BY C5.C5_PACIENT ORDER BY C5.C5_PACIENT "

        Case cTipoAuto == "MED"
            cCampo := "C5_MEDICO"
            cQry := " SELECT TOP 20 RTRIM(C5.C5_MEDICO) AS NOME, RTRIM(C5.C5_MEDICO) AS ID, '' AS INFO1, '' AS INFO2, '' AS INFO3 "
            cQry += " FROM " + RetSqlName("SC5") + " C5 WITH (NOLOCK) "
            cQry += " WHERE C5.D_E_L_E_T_ = ' ' AND RTRIM(ISNULL(C5.C5_MEDICO,'')) <> '' "
            For nI := 1 To Len(aTokens)
                cQry += " AND UPPER(C5.C5_MEDICO) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
            Next
            cQry += " GROUP BY C5.C5_MEDICO ORDER BY C5.C5_MEDICO "

        Case cTipoAuto == "CONV"
            cCampo := "C5_XCONVEN"
            cQry := " SELECT TOP 20 RTRIM(C5.C5_XCONVEN) AS NOME, RTRIM(C5.C5_XCODCON) AS ID, '' AS INFO1, '' AS INFO2, '' AS INFO3 "
            cQry += " FROM " + RetSqlName("SC5") + " C5 WITH (NOLOCK) "
            cQry += " WHERE C5.D_E_L_E_T_ = ' ' AND RTRIM(ISNULL(C5.C5_XCONVEN,'')) <> '' "
            For nI := 1 To Len(aTokens)
                cQry += " AND UPPER(C5.C5_XCONVEN) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
            Next
            cQry += " GROUP BY C5.C5_XCONVEN, C5.C5_XCODCON ORDER BY C5.C5_XCONVEN "

        Otherwise // CIR
            cCampo := "C5_MENNOTA"
            cQry := " SELECT TOP 20 RTRIM(C5.C5_MENNOTA) AS NOME, '' AS ID, '' AS INFO1, '' AS INFO2, '' AS INFO3 "
            cQry += " FROM " + RetSqlName("SC5") + " C5 WITH (NOLOCK) "
            cQry += " WHERE C5.D_E_L_E_T_ = ' ' AND RTRIM(ISNULL(C5.C5_MENNOTA,'')) <> '' "
            For nI := 1 To Len(aTokens)
                cQry += " AND UPPER(C5.C5_MENNOTA) LIKE '%" + fSolSqlEsc(Upper(aTokens[nI])) + "%' "
            Next
            cQry += " GROUP BY C5.C5_MENNOTA ORDER BY C5.C5_MENNOTA "
    EndCase

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    cJson := '{"ok":true,"itens":['

    While !(cAlias)->(Eof())
        If !lFirst
            cJson += ','
        EndIf
        lFirst := .F.

        If cTipoAuto == "HOSP"
            cInfo := AllTrim((cAlias)->INFO1)
            If !Empty(AllTrim((cAlias)->INFO2))
                cInfo += " · " + AllTrim((cAlias)->INFO2) + "/" + AllTrim((cAlias)->INFO3)
            EndIf
        ElseIf cTipoAuto == "MED" .And. !Empty(AllTrim((cAlias)->ID))
            cInfo := "CRM " + AllTrim((cAlias)->ID)
        Else
            cInfo := ""
        EndIf

        cJson += '{"id":"'   + fSolJsonEsc(AllTrim((cAlias)->ID)) + '",'
        If cTipoAuto == "HOSP"
            cJson += '"loja":"' + fSolJsonEsc(AllTrim((cAlias)->LOJA)) + '",'
        EndIf
        cJson += '"nome":"'  + fSolJsonEsc(AllTrim((cAlias)->NOME)) + '",'
        cJson += '"info":"'  + fSolJsonEsc(cInfo) + '"}'

        (cAlias)->(dbSkip())
    EndDo

    cJson += ']}'
    (cAlias)->(dbCloseArea())
Return cJson

Static Function fSolTokens(cQ)

    Local aRet  := {}
    Local cNorm := Upper(AllTrim(cQ))
    Local cTok  := ""
    Local nI    := 0
    Local c     := ""

    cNorm := StrTran(cNorm, ".", " ")
    cNorm := StrTran(cNorm, ",", " ")

    For nI := 1 To Len(cNorm)
        c := SubStr(cNorm, nI, 1)
        If c == " "
            If Len(cTok) >= 2
                aAdd(aRet, cTok)
            EndIf
            cTok := ""
        Else
            cTok += c
        EndIf
    Next

    If Len(cTok) >= 2
        aAdd(aRet, cTok)
    EndIf

    If Len(aRet) == 0 .And. Len(AllTrim(cQ)) >= 2
        aAdd(aRet, Upper(AllTrim(cQ)))
    EndIf
Return aRet

//=====================================================================
// Painel logistica - pedidos a atender / atendidos (SC5/SC6)
//=====================================================================
Static Function fSolPainel(cFil)

    Local cJson   := ""
    Local cQry    := ""
    Local cAlias  := GetNextAlias()
    Local cFilPV  := ""
    Local cNum    := ""
    Local cTipo   := ""
    Local lFirstP := .T.
    Local lFirstA := .T.
    Local nQtdP   := 0
    Local nQtdF   := 0

    cQry := " SELECT "
    cQry += "   RTRIM(C5.C5_FILIAL) AS C5_FILIAL, "
    cQry += "   RTRIM(C5.C5_NUM)    AS C5_NUM, "
    cQry += "   LEFT(RTRIM(C5.C5_NUM), 1) AS C5_TPSAIDA, "
    cQry += "   RTRIM(C5.C5_VEND1)  AS C5_VEND1, "
    cQry += "   RTRIM(A3.A3_NOME)   AS A3_NOME, "
    cQry += "   RTRIM(C5.C5_PACIENT) AS C5_PACIENT, "
    cQry += "   RTRIM(C5.C5_MEDICO) AS C5_XNOMEDI, "
    cQry += "   C5.C5_DTUSO         AS C5_DTUSO, "
    cQry += "   RTRIM(C5.C5_XCONVEN) AS C5_XCONVEN, "
    cQry += "   RTRIM(A1.A1_NOME)   AS A1_NOME, "
    cQry += "   SUM(C6.C6_QTDVEN)   AS QTD_PED, "
    cQry += "   SUM(C6.C6_QTDENT)   AS QTD_FAT "
    cQry += " FROM " + RetSqlName("SC5") + " C5 WITH (NOLOCK) "
    cQry += " INNER JOIN " + RetSqlName("SC6") + " C6 WITH (NOLOCK) "
    cQry += "   ON C6.D_E_L_E_T_ = ' ' AND C6.C6_FILIAL = C5.C5_FILIAL AND C6.C6_NUM = C5.C5_NUM "
    cQry += " LEFT JOIN " + RetSqlName("SA1") + " A1 WITH (NOLOCK) "
    cQry += "   ON A1.D_E_L_E_T_ = ' ' AND A1.A1_COD = C5.C5_CLIENTE AND A1.A1_LOJA = C5.C5_LOJACLI "
    cQry += " LEFT JOIN " + RetSqlName("SA3") + " A3 WITH (NOLOCK) "
    cQry += "   ON A3.D_E_L_E_T_ = ' ' AND A3.A3_COD = C5.C5_VEND1 "
    cQry += " WHERE C5.D_E_L_E_T_ = ' ' "
    cQry += "   AND C5.C5_EMISSAO >= '" + DToS(Date() - 30) + "' "
    cQry += "   AND LEFT(RTRIM(C5.C5_NUM), 1) IN ('R','C','P','N','M') "
    If !Empty(cFil)
        cQry += "   AND RTRIM(C5.C5_FILIAL) = '" + fSolSqlEsc(PadR(cFil, TamSX3("C5_FILIAL")[1])) + "' "
    EndIf
    cQry += " GROUP BY C5.C5_FILIAL, C5.C5_NUM, C5.C5_VEND1, A3.A3_NOME, "
    cQry += "   C5.C5_PACIENT, C5.C5_MEDICO, C5.C5_DTUSO, C5.C5_XCONVEN, A1.A1_NOME "
    cQry += " ORDER BY C5.C5_NUM DESC "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    cJson := '{"ok":true,"pendentes":['

    While !(cAlias)->(Eof())
        nQtdP := (cAlias)->QTD_PED
        nQtdF := (cAlias)->QTD_FAT
        If nQtdF < nQtdP
            If !lFirstP
                cJson += ','
            EndIf
            lFirstP := .F.
            cJson += fSolPnCard(AllTrim((cAlias)->C5_FILIAL), AllTrim((cAlias)->C5_NUM), AllTrim((cAlias)->C5_TPSAIDA), cAlias, .F.)
        EndIf
        (cAlias)->(dbSkip())
    EndDo

    cJson += '],"atendidos":['
    (cAlias)->(dbGoTop())
    While !(cAlias)->(Eof())
        nQtdP := (cAlias)->QTD_PED
        nQtdF := (cAlias)->QTD_FAT
        If nQtdF >= nQtdP .And. nQtdP > 0
            If !lFirstA
                cJson += ','
            EndIf
            lFirstA := .F.
            cJson += fSolPnCard(AllTrim((cAlias)->C5_FILIAL), AllTrim((cAlias)->C5_NUM), AllTrim((cAlias)->C5_TPSAIDA), cAlias, .T.)
        EndIf
        (cAlias)->(dbSkip())
    EndDo

    cJson += ']}'
    (cAlias)->(dbCloseArea())
Return cJson

Static Function fSolPnCard(cFil, cNum, cTipo, cAlias, lAtend)

    Local cJson  := ""
    Local cItens := fSolPnItens(cFil, cNum)

    cJson := '{'
    cJson += '"pedido":"'       + fSolJsonEsc(cNum) + '",'
    cJson += '"filial":"'       + fSolJsonEsc(cFil) + '",'
    cJson += '"tipo":"'         + fSolJsonEsc(cTipo) + '",'
    cJson += '"vendedor":"'     + fSolJsonEsc(AllTrim((cAlias)->C5_VEND1)) + '",'
    cJson += '"vendedorNome":"' + fSolJsonEsc(AllTrim((cAlias)->A3_NOME)) + '",'
    cJson += '"cliente":"'      + fSolJsonEsc(AllTrim((cAlias)->A1_NOME)) + '",'
    cJson += '"paciente":"'     + fSolJsonEsc(AllTrim((cAlias)->C5_PACIENT)) + '",'
    cJson += '"medico":"'       + fSolJsonEsc(AllTrim((cAlias)->C5_XNOMEDI)) + '",'
    cJson += '"dtUso":"'        + fSolJsonEsc(fSolFmtData((cAlias)->C5_DTUSO)) + '",'
    cJson += '"convenio":"'     + fSolJsonEsc(AllTrim((cAlias)->C5_XCONVEN)) + '",'
    cJson += '"atendido":'      + IIF(lAtend, "true", "false") + ','
    cJson += '"itens":'         + cItens
    cJson += '}'
Return cJson

Static Function fSolPnItens(cFil, cNum)

    Local cJson   := "["
    Local cQry    := ""
    Local cAlias  := GetNextAlias()
    Local lFirst  := .T.

    cQry := " SELECT RTRIM(C6.C6_PRODUTO) AS PRODUTO, "
    cQry += "        RTRIM(B1.B1_DESC) AS DESCR, "
    cQry += "        RTRIM(C6.C6_NUMSERI) AS SERIAL, "
    cQry += "        RTRIM(C6.C6_LOTECTL) AS LOTE, "
    cQry += "        C6.C6_QTDVEN AS QTD "
    cQry += " FROM " + RetSqlName("SC6") + " C6 WITH (NOLOCK) "
    cQry += " LEFT JOIN " + RetSqlName("SB1") + " B1 WITH (NOLOCK) "
    cQry += "   ON B1.D_E_L_E_T_ = ' ' AND B1.B1_COD = C6.C6_PRODUTO "
    cQry += " WHERE C6.D_E_L_E_T_ = ' ' "
    cQry += "   AND RTRIM(C6.C6_FILIAL) = '" + fSolSqlEsc(cFil) + "' "
    cQry += "   AND RTRIM(C6.C6_NUM) = '" + fSolSqlEsc(cNum) + "' "
    cQry += " ORDER BY C6.C6_ITEM "

    dbUseArea(.T., "TOPCONN", TCGenQry(,, cQry), cAlias, .F., .T.)

    While !(cAlias)->(Eof())
        If !lFirst
            cJson += ","
        EndIf
        lFirst := .F.
        cJson += '{"produto":"' + fSolJsonEsc(AllTrim((cAlias)->PRODUTO)) + '",'
        cJson += '"descricao":"' + fSolJsonEsc(AllTrim((cAlias)->DESCR)) + '",'
        cJson += '"serial":"' + fSolJsonEsc(AllTrim((cAlias)->SERIAL)) + '",'
        cJson += '"lote":"' + fSolJsonEsc(AllTrim((cAlias)->LOTE)) + '",'
        cJson += '"qtd":' + fSolJsonNum((cAlias)->QTD) + '}'
        (cAlias)->(dbSkip())
    EndDo

    cJson += "]"
    (cAlias)->(dbCloseArea())
Return cJson

//=====================================================================
// POST - Gerar pedido (MATA410) - baseado em WSRESERVA
//=====================================================================
Static Function fSolCriarPedido(oJson)

    Local aArea    := GetArea()
    Local aCabec   := {}
    Local aItens   := {}
    Local aLinha   := {}
    Local oItems   := Nil
    Local cVend    := AllTrim(oJson:GetJsonObject("vendedor"))
    Local cSenha   := AllTrim(oJson:GetJsonObject("senha"))
    Local cCliente := AllTrim(oJson:GetJsonObject("cliente"))
    Local cLoja    := AllTrim(oJson:GetJsonObject("loja"))
    Local cFil     := AllTrim(oJson:GetJsonObject("fil"))
    Local cTipo    := Upper(AllTrim(oJson:GetJsonObject("tipo")))
    Local cMedico  := AllTrim(oJson:GetJsonObject("medico"))
    Local cNomeMed := AllTrim(oJson:GetJsonObject("nomeMedico"))
    Local cPacient := AllTrim(oJson:GetJsonObject("paciente"))
    Local cConven  := AllTrim(oJson:GetJsonObject("convenio"))
    Local cCodConv := AllTrim(oJson:GetJsonObject("codConvenio"))
    Local cDtUso   := AllTrim(oJson:GetJsonObject("dtUso"))
    Local cHora    := AllTrim(oJson:GetJsonObject("hora"))
    Local cMenNota := AllTrim(oJson:GetJsonObject("mennota"))
    Local cObs     := AllTrim(oJson:GetJsonObject("obs"))
    Local cNumPed  := ""
    Local cJson    := ""
    Local cErro    := ""
    Local aLogAuto := {}
    Local nX       := 0
    Local nY       := 0
    Local nQtd     := 1
    Local nPreco   := 0
    Local cProd    := ""
    Local cLocal   := fSolArmEsperado(cTipo)
    Local cPref    := fSolPrefixoPV(cTipo)
    Local cTes     := "615"
    Local cMenFull := ""

    Private lMsErroAuto    := .F.
    Private lMsHelpAuto    := .T.
    Private lAutoErrNoFile := .T.

    If Empty(cVend) .Or. Empty(cSenha)
        RestArea(aArea)
        Return '{"ok":false,"msg":"Vendedor e senha obrigatorios"}'
    EndIf

    DbSelectArea("SA3")
    SA3->(DbSetOrder(1))
    If !SA3->(DbSeek(xFilial("SA3") + PadR(cVend, TamSX3("A3_COD")[1])))
        RestArea(aArea)
        Return '{"ok":false,"msg":"Vendedor nao encontrado"}'
    EndIf
    If AllTrim(SA3->A3_SENHA) <> cSenha
        RestArea(aArea)
        Return '{"ok":false,"msg":"Senha do vendedor invalida"}'
    EndIf

    If Empty(cCliente) .Or. Empty(cLoja)
        RestArea(aArea)
        Return '{"ok":false,"msg":"Cliente e loja obrigatorios"}'
    EndIf

    oItems := oJson:GetJsonObject("itens")
    If oItems == Nil .Or. Len(oItems) == 0
        RestArea(aArea)
        Return '{"ok":false,"msg":"Nenhum item informado"}'
    EndIf

    cNumPed := U_ProxPV(cPref)
    ConOut("[WSSOLPV] Gerando PV " + cNumPed + " tipo=" + cTipo + " vend=" + cVend)

    aAdd(aCabec, {"C5_NUM",     cNumPed,  Nil})
    aAdd(aCabec, {"C5_TPSAIDA", cTipo,    Nil})
    aAdd(aCabec, {"C5_TIPO",    "N",      Nil})
    aAdd(aCabec, {"C5_CLIENTE", cCliente, Nil})
    aAdd(aCabec, {"C5_LOJACLI", cLoja,    Nil})
    aAdd(aCabec, {"C5_LOJAENT", cLoja,    Nil})
    aAdd(aCabec, {"C5_CONDPAG", "002",    Nil})
    aAdd(aCabec, {"C5_VEND1",   cVend,    Nil})

    If !Empty(cMedico)
        aAdd(aCabec, {"C5_MEDICO",  cMedico,  Nil})
    EndIf
    If !Empty(cNomeMed)
        aAdd(aCabec, {"C5_XNOMEDI", cNomeMed, Nil})
    EndIf
    If !Empty(cPacient)
        aAdd(aCabec, {"C5_PACIENT", cPacient, Nil})
    EndIf
    If !Empty(cConven)
        aAdd(aCabec, {"C5_XCONVEN", cConven,  Nil})
    EndIf
    If !Empty(cCodConv)
        aAdd(aCabec, {"C5_XCODCON", cCodConv, Nil})
    EndIf
    If !Empty(cDtUso)
        aAdd(aCabec, {"C5_DTUSO",   CtoD(cDtUso), Nil})
    EndIf
    cMenFull := cMenNota
    If cTipo == "M"
        cMenFull := "SOLICITACAO DE MATERIAL - reserva estoque sem serial"
        If !Empty(cMenNota)
            cMenFull += " | " + cMenNota
        EndIf
    EndIf
    If !Empty(cObs)
        cMenFull += IIF(!Empty(cMenFull), " | ", "") + "Obs: " + cObs
    EndIf
    If !Empty(cMenFull)
        aAdd(aCabec, {"C5_MENNOTA", cMenFull, Nil})
    EndIf

    For nX := 1 To Len(oItems)
        aLinha := {}
        cProd  := AllTrim(oItems[nX]:GetJsonObject("produto"))
        nQtd   := 1
        nPreco := oItems[nX]:GetJsonObject("preco")

        If ValType(nPreco) != "N" .Or. nPreco <= 0
            nPreco := fSolPrecoProd(cCliente, cLoja, cProd)
        EndIf

        If cTipo == "M"
            nQtd := oItems[nX]:GetJsonObject("qtd")
            If ValType(nQtd) != "N" .Or. nQtd <= 0
                nQtd := 1
            EndIf
        EndIf

        aAdd(aLinha, {"C6_ITEM",    StrZero(nX, 2), Nil})
        aAdd(aLinha, {"C6_PRODUTO", cProd,          Nil})
        aAdd(aLinha, {"C6_QTDVEN",  nQtd,           Nil})
        aAdd(aLinha, {"C6_PRCVEN",  nPreco,         Nil})
        aAdd(aLinha, {"C6_VALOR",   nPreco * nQtd,  Nil})
        aAdd(aLinha, {"C6_TES",     cTes,           Nil})
        aAdd(aLinha, {"C6_LOCAL",   cLocal,         Nil})

        If cTipo != "M"
            aAdd(aLinha, {"C6_LOTECTL", AllTrim(oItems[nX]:GetJsonObject("lote")),   Nil})
            aAdd(aLinha, {"C6_NUMSERI", AllTrim(oItems[nX]:GetJsonObject("serial")), Nil})
            If !Empty(AllTrim(oItems[nX]:GetJsonObject("validade")))
                aAdd(aLinha, {"C6_DTVALID", StoD(AllTrim(oItems[nX]:GetJsonObject("validade"))), Nil})
            EndIf
        EndIf

        aAdd(aItens, aLinha)
    Next

    BeginTran()
    MsExecAuto({|x,y,z| MATA410(x,y,z)}, aCabec, aItens, 3, .F.)

    If lMsErroAuto
        RollBackSX8()
        DisarmTransaction()
        aLogAuto := GetAutoGRLog()
        For nY := 1 To Len(aLogAuto)
            cErro += aLogAuto[nY] + Chr(13) + Chr(10)
        Next
        ConOut("[WSSOLPV] ERRO ExecAuto: " + cErro)
        cJson := '{"ok":false,"msg":"Erro ao gerar pedido: ' + fSolJsonEsc(AllTrim(cErro)) + '"}'
    Else
        ConfirmSX8()
        EndTran()
        ConOut("[WSSOLPV] Pedido " + cNumPed + " gerado com sucesso")
        cJson := '{"ok":true,"pedido":"' + fSolJsonEsc(cNumPed) + '","tipo":"' + cTipo + '","msg":"Pedido gerado com sucesso"}'
    EndIf

    RestArea(aArea)
Return cJson

//=====================================================================
// Utilitarios JSON / SQL
//=====================================================================
Static Function fSolJsonEsc(cVal)
    Default cVal := ""
    cVal := AllTrim(cVal)
    cVal := StrTran(cVal, '\',  '\\')
    cVal := StrTran(cVal, '"',  '\"')
    cVal := StrTran(cVal, Chr(13), '')
    cVal := StrTran(cVal, Chr(10), '\n')
Return cVal

Static Function fSolSqlEsc(cVal)
    Default cVal := ""
    cVal := StrTran(AllTrim(cVal), "'", "''")
Return cVal

Static Function fSolJsonNum(nVal)
    Default nVal := 0
    If ValType(nVal) != "N"
        nVal := 0
    EndIf
Return StrTran(AllTrim(Str(nVal, 20, 2)), ",", ".")

Static Function fSolFmtData(xData)
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
