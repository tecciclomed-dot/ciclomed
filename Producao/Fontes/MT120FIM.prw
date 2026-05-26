#Include "Protheus.ch"
#Include "TopConn.ch"

/*/{Protheus.doc} MT120FIM
    Ponto de Entrada executado apos gravacao do Pedido de Compra (MATA120).
    O PC fica disponivel automaticamente no painel web (painel-compras.html).
    Nenhum email e enviado ao aprovador na inclusao do PC.
    O email ao comprador/solicitante e enviado somente na aprovacao/rejeicao (WSAPROVPC).
    @type  User Function
    @author Antonio
    @since 11/03/2026
    @version 2.0 - 26/05/2026: email ao aprovador substituido pelo painel web
/*/
User Function MT120FIM()
    Local aArea  := GetArea()
    Local nOpcao := PARAMIXB[1]  // 3=Inclusao, 4=Alteracao, 5=Exclusao
    Local cNumPC := PARAMIXB[2]  // Numero do PC
    Local nOpcA  := PARAMIXB[3]  // 1=Confirmado

    // Registra log para rastreabilidade - email ao aprovador suprimido:
    // o aprovador visualiza o PC diretamente no painel web (painel-compras.html).
    // Email ao comprador/solicitante e enviado apenas na aprovacao/rejeicao (WSAPROVPC).
    If nOpcA == 1
        ConOut("[MT120FIM] PC " + AllTrim(cNumPC) + " incluido no painel de aprovacao.")
    EndIf

    RestArea(aArea)
Return

/*/{Protheus.doc} fEnvEmailAprov
    Busca o aprovador e envia email com detalhes do PC.
    @type  Static Function
    @author Antonio
    @since 11/03/2026
/*/
Static Function fEnvEmailAprov(cNumPC)
    Local aArea      := GetArea()
    Local aAreaSC7   := SC7->(GetArea())
    Local cUserId    := RetCodUsr()
    Local cEmailAprov := ""
    Local cNomeAprov  := ""
    Local cAssunto   := ""
    Local cCorpo     := ""

    ConOut("[MT120FIM] Buscando aprovador para user: " + cUserId)

    // Busca email do aprovador pela cadeia: Comprador -> Grupo -> Aprovador -> Email
    fGetAprovEmail(cUserId, @cEmailAprov, @cNomeAprov)

    If Empty(cEmailAprov)
        ConOut("[MT120FIM] AVISO: Nenhum email de aprovador encontrado para user " + cUserId)
        RestArea(aAreaSC7)
        RestArea(aArea)
        Return
    EndIf

    ConOut("[MT120FIM] Aprovador: " + AllTrim(cNomeAprov) + " - Email: " + AllTrim(cEmailAprov))

    // Monta assunto e corpo do email
    cAssunto := "PC " + AllTrim(cNumPC) + " aguardando aprovacao - " + AllTrim(FunName()) + " " + DToC(dDataBase)
    cCorpo   := fMontaCorpoPC(cNumPC)

    If Empty(cCorpo)
        ConOut("[MT120FIM] Erro ao montar corpo do email para PC: " + AllTrim(cNumPC))
        RestArea(aAreaSC7)
        RestArea(aArea)
        Return
    EndIf

    // Envia o email
    If fSendMailPC(AllTrim(cEmailAprov), cAssunto, cCorpo)
        MsgInfo("Email de aprovacao do PC " + AllTrim(cNumPC) + " enviado para " + AllTrim(cNomeAprov) + " (" + AllTrim(cEmailAprov) + ")", "Email Enviado")
        ConOut("[MT120FIM] Email enviado com sucesso para " + AllTrim(cEmailAprov))
    Else
        ConOut("[MT120FIM] FALHA ao enviar email para " + AllTrim(cEmailAprov))
    EndIf

    RestArea(aAreaSC7)
    RestArea(aArea)
Return

/*/{Protheus.doc} fGetAprovEmail
    Busca email do aprovador via cadeia SY1 -> SAL -> SAK -> SYS_USR.
    @type  Static Function
    @param cUserId    - ID do usuario logado (comprador)
    @param cEmailAprov - Retorno: email do aprovador
    @param cNomeAprov  - Retorno: nome do aprovador
    @author Antonio
    @since 11/03/2026
/*/
Static Function fGetAprovEmail(cUserId, cEmailAprov, cNomeAprov)
    Local cQuery  := ""
    Local cAlias  := GetNextAlias()

    cQuery := " SELECT TOP 1 USR.USR_EMAIL, USR.USR_NOME "
    cQuery += " FROM " + RetSQLName("SY1") + " SY1 "
    cQuery += " INNER JOIN " + RetSQLName("SAL") + " SAL "
    cQuery += "   ON SAL.AL_COD = SY1.Y1_GRAPROV "
    cQuery += "   AND SAL.D_E_L_E_T_ = ' ' "
    cQuery += " INNER JOIN " + RetSQLName("SAK") + " SAK "
    cQuery += "   ON SAK.AK_FILIAL = SAL.AL_FILIAL "
    cQuery += "   AND SAK.AK_COD = SAL.AL_APROV "
    cQuery += "   AND SAK.D_E_L_E_T_ = ' ' "
    cQuery += " INNER JOIN SYS_USR USR "
    cQuery += "   ON USR.USR_ID = SAK.AK_USER "
    cQuery += " WHERE SY1.Y1_USER = '" + cUserId + "' "
    cQuery += "   AND SY1.D_E_L_E_T_ = ' ' "

    cQuery := ChangeQuery(cQuery)

    If Select(cAlias) > 0
        (cAlias)->(dbCloseArea())
    EndIf

    dbUseArea(.T., "TOPCONN", TCGenQry(,,cQuery), cAlias, .T., .T.)

    If !(cAlias)->(Eof())
        cEmailAprov := AllTrim((cAlias)->USR_EMAIL)
        cNomeAprov  := AllTrim((cAlias)->USR_NOME)
    EndIf

    (cAlias)->(dbCloseArea())
Return

/*/{Protheus.doc} fMontaCorpoPC
    Monta corpo HTML do email com os detalhes do Pedido de Compra.
    @type  Static Function
    @param cNumPC - Numero do PC
    @return cHtml - Corpo HTML do email
    @author Antonio
    @since 11/03/2026
/*/
Static Function fMontaCorpoPC(cNumPC)
    Local cHtml      := ""
    Local aAreaSC7   := SC7->(GetArea())
    Local cFornece   := ""
    Local cNomeForn  := ""
    Local nTotalPC   := 0
    Local cComprador := ""
    Local cFilPC     := xFilial("SC7")
    Local cBaseUrl   := "https://marcossrdg.github.io/rdmake_Ciclo/docs/aprovacao-pc.html"
    Local cItem      := ""
    Local cTkAprov   := ""
    Local cTkRejeit  := ""
    Local cTkApTodos := ""
    Local cTkRjTodos := ""
    Local cBtnStyle  := ""

    // Posiciona no primeiro item do PC
    dbSelectArea("SC7")
    SC7->(dbSetOrder(1))

    If !SC7->(dbSeek(cFilPC + cNumPC))
        ConOut("[MT120FIM] PC nao encontrado: " + cNumPC)
        RestArea(aAreaSC7)
        Return ""
    EndIf

    // Dados do cabecalho
    cFornece := AllTrim(SC7->C7_FORNECE) + "/" + AllTrim(SC7->C7_LOJA)
    cNomeForn := AllTrim(Posicione("SA2", 1, xFilial("SA2") + SC7->(C7_FORNECE + C7_LOJA), "A2_NOME"))
    cComprador := AllTrim(Posicione("SY1", 3, xFilial("SY1") + SC7->C7_USER, "Y1_NOME"))

    // Tokens para aprovar/rejeitar TODOS
    cTkApTodos := U_GeraTokenPC(AllTrim(cNumPC), "ALL", "A", cFilPC)
    cTkRjTodos := U_GeraTokenPC(AllTrim(cNumPC), "ALL", "R", cFilPC)

    // Cabecalho HTML
    cHtml := '<html><head><meta charset="UTF-8"></head><body>'
    cHtml += '<div style="font-family:Arial,sans-serif;max-width:800px;margin:0 auto;">'
    cHtml += '<div style="background:#1a5276;color:#fff;padding:15px 20px;border-radius:5px 5px 0 0;">'
    cHtml += '<h2 style="margin:0;">Pedido de Compra Pendente de Aprova&ccedil;&atilde;o</h2>'
    cHtml += '</div>'
    cHtml += '<div style="border:1px solid #ddd;padding:20px;border-radius:0 0 5px 5px;">'

    // Info geral
    cHtml += '<table style="width:100%;border-collapse:collapse;margin-bottom:15px;">'
    cHtml += '<tr><td style="padding:5px;font-weight:bold;width:150px;">N&ordm; do PC:</td>'
    cHtml += '<td style="padding:5px;"><strong>' + AllTrim(cNumPC) + '</strong></td></tr>'
    cHtml += '<tr><td style="padding:5px;font-weight:bold;">Data Emiss&atilde;o:</td>'
    cHtml += '<td style="padding:5px;">' + DToC(SC7->C7_EMISSAO) + '</td></tr>'
    cHtml += '<tr><td style="padding:5px;font-weight:bold;">Fornecedor:</td>'
    cHtml += '<td style="padding:5px;">' + cFornece + ' - ' + cNomeForn + '</td></tr>'
    cHtml += '<tr><td style="padding:5px;font-weight:bold;">Comprador:</td>'
    cHtml += '<td style="padding:5px;">' + cComprador + '</td></tr>'
    cHtml += '</table>'

    // Botoes APROVAR TODOS / REJEITAR TODOS
    cHtml += '<div style="text-align:center;margin-bottom:15px;">'
    cHtml += '<a href="' + cBaseUrl + '?pc=' + AllTrim(cNumPC) + '&item=ALL&acao=A&fil=' + AllTrim(cFilPC) + '&token=' + cTkApTodos + '" '
    cHtml += 'style="display:inline-block;padding:10px 25px;background:#27ae60;color:#fff;text-decoration:none;'
    cHtml += 'border-radius:5px;font-weight:bold;font-size:14px;margin:5px;">&#10003; APROVAR TODOS</a>'
    cHtml += '<a href="' + cBaseUrl + '?pc=' + AllTrim(cNumPC) + '&item=ALL&acao=R&fil=' + AllTrim(cFilPC) + '&token=' + cTkRjTodos + '" '
    cHtml += 'style="display:inline-block;padding:10px 25px;background:#c0392b;color:#fff;text-decoration:none;'
    cHtml += 'border-radius:5px;font-weight:bold;font-size:14px;margin:5px;">&#10007; REJEITAR TODOS</a>'
    cHtml += '</div>'

    cHtml += '<p style="text-align:center;color:#888;font-size:12px;margin-bottom:15px;">'
    cHtml += 'Ou aprove/rejeite cada item individualmente:'
    cHtml += '</p>'

    // Tabela de itens com botoes
    cHtml += '<table style="width:100%;border-collapse:collapse;border:1px solid #ddd;">'
    cHtml += '<tr style="background:#2c3e50;color:#fff;">'
    cHtml += '<th style="padding:8px;text-align:left;">Item</th>'
    cHtml += '<th style="padding:8px;text-align:left;">Produto</th>'
    cHtml += '<th style="padding:8px;text-align:left;">Descri&ccedil;&atilde;o</th>'
    cHtml += '<th style="padding:8px;text-align:center;">UM</th>'
    cHtml += '<th style="padding:8px;text-align:right;">Qtd</th>'
    cHtml += '<th style="padding:8px;text-align:right;">Vlr.Unit</th>'
    cHtml += '<th style="padding:8px;text-align:right;">Total</th>'
    cHtml += '<th style="padding:8px;text-align:center;">A&ccedil;&atilde;o</th>'
    cHtml += '</tr>'

    While !SC7->(Eof()) .And. SC7->(C7_FILIAL + C7_NUM) == cFilPC + cNumPC
        nTotalPC += SC7->C7_TOTAL
        cItem := AllTrim(SC7->C7_ITEM)

        // Gera tokens para este item
        cTkAprov  := U_GeraTokenPC(AllTrim(cNumPC), cItem, "A", cFilPC)
        cTkRejeit := U_GeraTokenPC(AllTrim(cNumPC), cItem, "R", cFilPC)

        cHtml += '<tr style="border-bottom:1px solid #eee;">'
        cHtml += '<td style="padding:6px;">' + cItem + '</td>'
        cHtml += '<td style="padding:6px;">' + AllTrim(SC7->C7_PRODUTO) + '</td>'
        cHtml += '<td style="padding:6px;">' + AllTrim(SC7->C7_DESCRI) + '</td>'
        cHtml += '<td style="padding:6px;text-align:center;">' + AllTrim(SC7->C7_UM) + '</td>'
        cHtml += '<td style="padding:6px;text-align:right;">' + AllTrim(Transform(SC7->C7_QUANT, "@E 999,999.9999")) + '</td>'
        cHtml += '<td style="padding:6px;text-align:right;">R$ ' + AllTrim(Transform(SC7->C7_PRECO, "@E 999,999,999.99")) + '</td>'
        cHtml += '<td style="padding:6px;text-align:right;">R$ ' + AllTrim(Transform(SC7->C7_TOTAL, "@E 999,999,999.99")) + '</td>'
        cHtml += '<td style="padding:6px;text-align:center;white-space:nowrap;">'
        // Botao Aprovar
        cBtnStyle := "display:inline-block;padding:4px 10px;background:#27ae60;color:#fff;text-decoration:none;border-radius:3px;font-size:11px;font-weight:bold;"
        cHtml += '<a href="' + cBaseUrl + '?pc=' + AllTrim(cNumPC) + '&item=' + cItem + '&acao=A&fil=' + AllTrim(cFilPC) + '&token=' + cTkAprov + '" '
        cHtml += 'style="' + cBtnStyle + '">&#10003;</a> '
        // Botao Rejeitar
        cBtnStyle := "display:inline-block;padding:4px 10px;background:#c0392b;color:#fff;text-decoration:none;border-radius:3px;font-size:11px;font-weight:bold;"
        cHtml += '<a href="' + cBaseUrl + '?pc=' + AllTrim(cNumPC) + '&item=' + cItem + '&acao=R&fil=' + AllTrim(cFilPC) + '&token=' + cTkRejeit + '" '
        cHtml += 'style="' + cBtnStyle + '">&#10007;</a>'
        cHtml += '</td>'
        cHtml += '</tr>'

        // Linha da Justificativa
        cHtml += '<tr style="border-bottom:1px solid #ddd;background:#f9f9f9;">'
        cHtml += '<td style="padding:4px 6px;font-size:11px;color:#888;">Justif.:</td>'
        cHtml += '<td colspan="7" style="padding:4px 6px;font-size:11px;color:#555;font-style:italic;">'
        If !Empty(AllTrim(SC7->C7_JUSTIFI))
            cHtml += AllTrim(SC7->C7_JUSTIFI)
        Else
            cHtml += '<span style="color:#ccc;">Sem justificativa</span>'
        EndIf
        cHtml += '</td></tr>'

        SC7->(dbSkip())
    EndDo

    // Total
    cHtml += '<tr style="background:#ecf0f1;font-weight:bold;">'
    cHtml += '<td colspan="7" style="padding:8px;text-align:right;">TOTAL DO PEDIDO:</td>'
    cHtml += '<td style="padding:8px;text-align:right;">R$ ' + AllTrim(Transform(nTotalPC, "@E 999,999,999.99")) + '</td>'
    cHtml += '</tr>'
    cHtml += '</table>'

    // Rodape
    cHtml += '<p style="margin-top:15px;color:#666;font-size:12px;">'
    cHtml += 'Clique nos bot&otilde;es acima para aprovar ou rejeitar. '
    cHtml += 'Voc&ecirc; tamb&eacute;m pode acessar SIGACOM &gt; Libera&ccedil;&atilde;o de Pedidos (MATA126).'
    cHtml += '</p>'

    cHtml += '</div></div></body></html>'

    RestArea(aAreaSC7)
Return cHtml

/*/{Protheus.doc} fSendMailPC
    Envia email via SMTP usando parametros MV_REL*.
    @type  Static Function
    @param cDest    - Email destino
    @param cAssunto - Assunto do email
    @param cCorpo   - Corpo HTML
    @return lRet    - .T. se enviou com sucesso
    @author Antonio
    @since 11/03/2026
/*/
Static Function fSendMailPC(cDest, cAssunto, cCorpo)
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

    // Separa host e porta se vier no formato "host:porta"
    If nPosPort > 0
        nPorta    := Val(SubStr(cServidor, nPosPort + 1))
        cServidor := Left(cServidor, nPosPort - 1)
    EndIf

    ConOut("[MT120FIM] SMTP: " + cServidor + " | User: " + cUsuario + " | Dest: " + cDest)

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
        ConOut("[MT120FIM] Erro Init SMTP: " + oServer:GetErrorString(nStatus))
        Return .F.
    EndIf

    nStatus := oServer:SetSmtpTimeOut(120)

    nStatus := oServer:SMTPConnect()
    If nStatus != 0
        ConOut("[MT120FIM] Erro SMTPConnect: " + oServer:GetErrorString(nStatus))
        Return .F.
    EndIf

    If lAuth
        nStatus := oServer:SMTPAuth(cUsuario, cSenha)
        If nStatus != 0
            ConOut("[MT120FIM] Erro SMTPAuth: " + oServer:GetErrorString(nStatus))
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
        ConOut("[MT120FIM] Erro Send: " + oServer:GetErrorString(nStatus))
    Else
        ConOut("[MT120FIM] Email enviado com sucesso!")
        lRet := .T.
    EndIf

    oServer:SMTPDisconnect()
Return lRet
