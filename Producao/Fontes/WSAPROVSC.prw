#Include "Protheus.ch"
#Include "TopConn.ch"
#Include "RESTFUL.ch"

/*/{Protheus.doc} WSAPROVSC
    REST API para aprovacao/rejeicao de Solicitacoes de Compra (SC1) via painel web.
    Usa token MD5 para autenticacao sem login.

    GET /rest03/WSAPROVSC?sc=XXXXXX&item=XXXX&acao=A&fil=XX&token=HASH

    Se item=ALL, aprova/rejeita todos os itens da SC.
    Token: MD5("CICLO2026SC#" + fil + "#" + sc + "#" + item + "#" + acao)

    @type  WSRESTFUL
    @author Antonio
    @since 26/05/2026
/*/

WSRESTFUL WSAPROVSC DESCRIPTION "Aprovacao de Solicitacao de Compra via painel web"

    WSDATA sc    AS STRING
    WSDATA item  AS STRING
    WSDATA acao  AS STRING
    WSDATA fil   AS STRING
    WSDATA token AS STRING

    WSMETHOD GET DESCRIPTION "Aprovar ou Rejeitar item(ns) da Solicitacao de Compra" WSSYNTAX "/WSAPROVSC?sc={sc}&item={item}&acao={acao}&fil={fil}&token={token}"

END WSRESTFUL

WSMETHOD GET WSRECEIVE sc, item, acao, fil, token WSSERVICE WSAPROVSC

    Local cNumSC  := AllTrim(::sc)
    Local cItem   := Upper(AllTrim(::item))
    Local cAcao   := Upper(AllTrim(::acao))
    Local cFilSC  := PadR(AllTrim(::fil), TamSX3("C1_FILIAL")[1])
    Local cToken  := AllTrim(::token)
    Local cTokenEsp := ""
    Local cJson   := ""
    Local nAprov  := 0
    Local nFalha  := 0
    Local aArea   := GetArea()
    Local aAreaSC1 := SC1->(GetArea())

    ::SetContentType("application/json")
    ::SetHeader("Access-Control-Allow-Origin",  "*")
    ::SetHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
    ::SetHeader("Access-Control-Allow-Headers", "Authorization, Content-Type")

    ConOut("[WSAPROVSC] SC=" + cNumSC + " Item=" + cItem + " Acao=" + cAcao + " Fil=" + cFilSC)

    If Empty(cNumSC) .Or. Empty(cItem) .Or. Empty(cAcao) .Or. Empty(cToken) .Or. Empty(cFilSC)
        ::SetResponse('{"ok":false,"msg":"Parametros incompletos"}')
        RestArea(aAreaSC1)
        RestArea(aArea)
        Return .T.
    EndIf

    cTokenEsp := MD5("CICLO2026SC#" + AllTrim(::fil) + "#" + cNumSC + "#" + cItem + "#" + cAcao)
    If cToken != cTokenEsp
        ConOut("[WSAPROVSC] Token invalido - esp=" + cTokenEsp + " rec=" + cToken)
        ::SetResponse('{"ok":false,"msg":"Token invalido"}')
        RestArea(aAreaSC1)
        RestArea(aArea)
        Return .T.
    EndIf

    If cItem == "ALL"
        dbSelectArea("SC1")
        SC1->(dbSetOrder(1))
        If SC1->(dbSeek(cFilSC + cNumSC))
            While !SC1->(Eof()) .And. SC1->(C1_FILIAL + C1_NUM) == cFilSC + cNumSC
                If cAcao == "A"
                    If fAprovarItemSC(cNumSC, AllTrim(SC1->C1_ITEM), cFilSC)
                        nAprov++
                    Else
                        nFalha++
                    EndIf
                ElseIf cAcao == "R"
                    If fRejeitarItemSC(cNumSC, AllTrim(SC1->C1_ITEM), cFilSC)
                        nAprov++
                    Else
                        nFalha++
                    EndIf
                EndIf
                SC1->(dbSkip())
            EndDo
        EndIf

        If nAprov > 0
            fNotificaSolicitante(cNumSC, cAcao, cValToChar(nAprov), "ALL", cFilSC)
        EndIf

        cJson := '{"ok":true,"msg":"' + If(cAcao=="A","Aprovado","Rejeitado") + '",'
        cJson += '"processados":' + cValToChar(nAprov) + ',"ignorados":' + cValToChar(nFalha) + '}'

    Else
        If cAcao == "A"
            If fAprovarItemSC(cNumSC, cItem, cFilSC)
                fNotificaSolicitante(cNumSC, cAcao, "1", cItem, cFilSC)
                cJson := '{"ok":true,"msg":"Item ' + cItem + ' aprovado com sucesso"}'
            Else
                cJson := '{"ok":false,"msg":"Nao foi possivel aprovar o item ' + cItem + '. Verifique se ja foi processado."}'
            EndIf
        ElseIf cAcao == "R"
            If fRejeitarItemSC(cNumSC, cItem, cFilSC)
                fNotificaSolicitante(cNumSC, cAcao, "1", cItem, cFilSC)
                cJson := '{"ok":true,"msg":"Item ' + cItem + ' rejeitado"}'
            Else
                cJson := '{"ok":false,"msg":"Nao foi possivel rejeitar o item ' + cItem + '."}'
            EndIf
        Else
            cJson := '{"ok":false,"msg":"Acao invalida. Use A=Aprovar ou R=Rejeitar."}'
        EndIf
    EndIf

    ::SetResponse(cJson)
    RestArea(aAreaSC1)
    RestArea(aArea)
Return .T.

//-------------------------------------------------------------------
Static Function fAprovarItemSC(cNumSC, cItem, cFilSC)
    Local aArea    := GetArea()
    Local aAreaSC1 := SC1->(GetArea())
    Local lRet     := .F.

    dbSelectArea("SC1")
    SC1->(dbSetOrder(1))

    If SC1->(dbSeek(cFilSC + cNumSC + cItem))
        If AllTrim(SC1->C1_APROV) != "L" .And. AllTrim(SC1->C1_APROV) != "R"
            If RecLock("SC1", .F.)
                SC1->C1_APROV := "L"
                MsUnlock()
                lRet := .T.
                ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " APROVADO")
            EndIf
        Else
            ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " ja com status: " + AllTrim(SC1->C1_APROV))
        EndIf
    Else
        ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " NAO encontrado")
    EndIf

    RestArea(aAreaSC1)
    RestArea(aArea)
Return lRet

//-------------------------------------------------------------------
Static Function fRejeitarItemSC(cNumSC, cItem, cFilSC)
    Local aArea    := GetArea()
    Local aAreaSC1 := SC1->(GetArea())
    Local lRet     := .F.

    dbSelectArea("SC1")
    SC1->(dbSetOrder(1))

    If SC1->(dbSeek(cFilSC + cNumSC + cItem))
        If AllTrim(SC1->C1_APROV) != "L" .And. AllTrim(SC1->C1_APROV) != "R"
            If RecLock("SC1", .F.)
                SC1->C1_APROV := "R"
                MsUnlock()
                lRet := .T.
                ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " REJEITADO")
            EndIf
        Else
            ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " ja com status: " + AllTrim(SC1->C1_APROV))
        EndIf
    Else
        ConOut("[WSAPROVSC] Item " + cItem + " SC " + cNumSC + " NAO encontrado")
    EndIf

    RestArea(aAreaSC1)
    RestArea(aArea)
Return lRet

//-------------------------------------------------------------------
// Envia email ao solicitante informando aprovacao/rejeicao da SC
//-------------------------------------------------------------------
Static Function fNotificaSolicitante(cNumSC, cAcao, cQtd, cItem, cFilSC)
    Local aArea      := GetArea()
    Local aAreaSC1   := SC1->(GetArea())
    Local cEmailSol  := ""
    Local cNomeSol   := ""
    Local cAssunto   := ""
    Local cCorpo     := ""
    Local cStatus    := If(cAcao == "A", "APROVADA", "REJEITADA")
    Local cCorStatus := If(cAcao == "A", "#27ae60", "#c0392b")
    Local cIcone     := If(cAcao == "A", "&#10003;", "&#10007;")

    fGetSolicitanteEmail(cNumSC, cFilSC, @cEmailSol, @cNomeSol)

    If Empty(cEmailSol)
        ConOut("[WSAPROVSC] Nenhum email de solicitante para SC " + cNumSC)
        RestArea(aAreaSC1)
        RestArea(aArea)
        Return
    EndIf

    If cItem == "ALL"
        cAssunto := "SC " + AllTrim(cNumSC) + " " + cStatus + " (" + cQtd + " itens) - " + DToC(dDataBase)
    Else
        cAssunto := "SC " + AllTrim(cNumSC) + " Item " + cItem + " " + cStatus + " - " + DToC(dDataBase)
    EndIf

    cCorpo := '<html><head><meta charset="UTF-8"></head><body>'
    cCorpo += '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">'
    cCorpo += '<div style="background:' + cCorStatus + ';color:#fff;padding:15px 20px;border-radius:5px 5px 0 0;text-align:center;">'
    cCorpo += '<span style="font-size:40px;">' + cIcone + '</span>'
    cCorpo += '<h2 style="margin:10px 0 0;">Solicitacao de Compra ' + cStatus + '</h2>'
    cCorpo += '</div>'
    cCorpo += '<div style="border:1px solid #ddd;padding:20px;border-radius:0 0 5px 5px;">'
    cCorpo += '<table style="width:100%;border-collapse:collapse;">'
    cCorpo += '<tr><td style="padding:5px;font-weight:bold;width:150px;">N&ordm; da SC:</td>'
    cCorpo += '<td style="padding:5px;"><strong>' + AllTrim(cNumSC) + '</strong></td></tr>'
    cCorpo += '<tr><td style="padding:5px;font-weight:bold;">Data:</td>'
    cCorpo += '<td style="padding:5px;">' + DToC(dDataBase) + '</td></tr>'
    cCorpo += '<tr><td style="padding:5px;font-weight:bold;">Status:</td>'
    cCorpo += '<td style="padding:5px;color:' + cCorStatus + ';font-weight:bold;">' + cStatus + '</td></tr>'
    cCorpo += '</table>'

    If cAcao == "A"
        cCorpo += '<p style="color:#27ae60;">Sua solicita&ccedil;&atilde;o foi aprovada e estar&aacute; disponivel para gera&ccedil;&atilde;o do Pedido de Compra.</p>'
    Else
        cCorpo += '<p style="color:#c0392b;">Sua solicita&ccedil;&atilde;o foi rejeitada. Entre em contato com o aprovador para mais detalhes.</p>'
    EndIf

    cCorpo += '<p style="color:#999;font-size:12px;margin-top:20px;">Mensagem autom&aacute;tica - Protheus CicloMed</p>'
    cCorpo += '</div></div></body></html>'

    fSendMailSC(AllTrim(cEmailSol), cAssunto, cCorpo)

    RestArea(aAreaSC1)
    RestArea(aArea)
Return

//-------------------------------------------------------------------
Static Function fGetSolicitanteEmail(cNumSC, cFilSC, cEmail, cNome)
    Local cQry  := ""
    Local cAli  := GetNextAlias()
    Local aAreaSC1 := SC1->(GetArea())

    Default cEmail := ""
    Default cNome  := ""

    dbSelectArea("SC1")
    SC1->(dbSetOrder(1))

    If !SC1->(dbSeek(cFilSC + cNumSC))
        RestArea(aAreaSC1)
        Return
    EndIf

    cQry := " SELECT USR.USR_EMAIL, USR.USR_NOME "
    cQry += " FROM SYS_USR USR "
    cQry += " WHERE USR.USR_ID = '" + AllTrim(SC1->C1_USER) + "' "
    cQry := ChangeQuery(cQry)

    If Select(cAli) > 0
        (cAli)->(dbCloseArea())
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,,cQry), cAli, .T., .T.)
    If !(cAli)->(Eof())
        cEmail := AllTrim((cAli)->USR_EMAIL)
        cNome  := AllTrim((cAli)->USR_NOME)
    EndIf
    (cAli)->(dbCloseArea())

    RestArea(aAreaSC1)
Return

//-------------------------------------------------------------------
Static Function fSendMailSC(cDest, cAssunto, cCorpo)
    Local oServer   := Nil
    Local oMessage  := Nil
    Local nStatus   := 0
    Local cServidor := AllTrim(SuperGetMv("MV_RELSERV",, "smtp.office365.com:587"))
    Local cUsuario  := AllTrim(SuperGetMv("MV_RELAUSR",, "protheus@ciclomed.com.br"))
    Local cSenha    := AllTrim(SuperGetMv("MV_RELAPSW",, ""))
    Local lSSL      := SuperGetMv("MV_RELSSL",, .F.)
    Local lTLS      := SuperGetMv("MV_RELTLS",, .T.)
    Local lAuth     := SuperGetMv("MV_RELAUTH",, .T.)
    Local lRet      := .F.
    Local nPorta    := 587
    Local nPosPort  := At(":", cServidor)

    If nPosPort > 0
        nPorta    := Val(SubStr(cServidor, nPosPort + 1))
        cServidor := Left(cServidor, nPosPort - 1)
    EndIf

    ConOut("[WSAPROVSC] SMTP: " + cServidor + " | Dest: " + cDest)

    oServer := tMailManager():New()

    If ValType(lSSL) == "C"
        lSSL := (Upper(AllTrim(lSSL)) == ".T.")
    EndIf
    If ValType(lTLS) == "C"
        lTLS := (Upper(AllTrim(lTLS)) == ".T.")
    EndIf
    If ValType(lAuth) == "C"
        lAuth := (Upper(AllTrim(lAuth)) == ".T.")
    EndIf

    If lSSL
        oServer:SetUseSSL(.T.)
    EndIf
    If lTLS
        oServer:SetUseTLS(.T.)
    EndIf

    nStatus := oServer:Init("", cServidor, cUsuario, cSenha,, nPorta)
    If nStatus != 0
        ConOut("[WSAPROVSC] Erro Init SMTP: " + oServer:GetErrorString(nStatus))
        Return .F.
    EndIf

    oServer:SetSmtpTimeOut(120)

    nStatus := oServer:SMTPConnect()
    If nStatus != 0
        ConOut("[WSAPROVSC] Erro SMTPConnect: " + oServer:GetErrorString(nStatus))
        Return .F.
    EndIf

    If lAuth
        nStatus := oServer:SMTPAuth(cUsuario, cSenha)
        If nStatus != 0
            ConOut("[WSAPROVSC] Erro SMTPAuth: " + oServer:GetErrorString(nStatus))
            oServer:SMTPDisconnect()
            Return .F.
        EndIf
    EndIf

    oMessage := tMailMessage():New()
    oMessage:Clear()
    oMessage:cFrom    := cUsuario
    oMessage:cTo      := cDest
    oMessage:cSubject := cAssunto
    oMessage:cBody    := cCorpo
    oMessage:MsgBodyType("text/html")

    nStatus := oMessage:Send(oServer)

    If nStatus != 0
        ConOut("[WSAPROVSC] Erro Send: " + oServer:GetErrorString(nStatus))
    Else
        ConOut("[WSAPROVSC] Email enviado com sucesso para " + cDest)
        lRet := .T.
    EndIf

    oServer:SMTPDisconnect()
Return lRet
