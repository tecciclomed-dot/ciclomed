#Include "Protheus.ch"

/*/{Protheus.doc} CMAPUrlBase
    URL base das paginas HTML de aprovacao (GitHub Pages / CicloMed).
    Parametro MV_URLAPROV: ex. https://marcossrdg.github.io/rdmake_Ciclo/docs
    @type  User Function
    @author Antonio
    @since 19/05/2026
/*/
User Function CMAPUrlBase()
    Local cUrl := AllTrim(GetNewPar("MV_URLAPROV", "https://tecciclomed-dot.github.io/ciclomed"))
    If Right(cUrl, 1) == "/"
        cUrl := Left(cUrl, Len(cUrl) - 1)
    EndIf
Return cUrl

/*/{Protheus.doc} CMAGTkSC
    Token VIEW para painel-sc.html (WSSCPAINEL).
    Nome curto: ADVPL limita simbolo User Function a 10 caracteres (U_CMAGTkSC).
    @type  User Function
/*/
User Function CMAGTkSC(cSC, cFil)
Return MD5("CICLO2026SC#" + AllTrim(PadR(cFil, 2)) + "#" + AllTrim(cSC) + "#VIEW#V")

/*/{Protheus.doc} CMAGTkPC
    Token VIEW para painel-pc.html (WSPCPAINEL).
    @type  User Function
/*/
User Function CMAGTkPC(cPC, cFil)
Return MD5("CICLO2026PC#" + AllTrim(PadR(cFil, 2)) + "#" + AllTrim(cPC) + "#VIEW#V")

/*/{Protheus.doc} CMAGTkBx
    Token para WSAPROVINBOX / aprovacoes.html.
    @type  User Function
/*/
User Function CMAGTkBx(cApr)
Return MD5("CICLO2026INBOX#" + AllTrim(cApr))

/*/{Protheus.doc} CMAPTkCP
    Token de acesso ao painel de compras do aprovador (WSPAINELCP / painel-compras.html).
    O token inclui o codigo do aprovador: cada aprovador tem sua propria URL exclusiva.
    Uso: U_CMAPUrlBase() + "/painel-compras.html?apr=" + cApr + "&token=" + U_CMAPTkCP(cApr)
    @type  User Function
    @param cApr - Codigo do usuario aprovador (AK_USER / SAK)
/*/
User Function CMAPTkCP(cApr)
    Default cApr := ""
Return MD5("CICLO2026PAINEL#CP#" + AllTrim(cApr))
