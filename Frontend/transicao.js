/* =========================================================
   Transição entre páginas do EduFix (mesmo efeito do app Ionic/Material)
   Carregado no <head> de todas as páginas, antes do style.css.

   O que faz:
   1) Navegadores com "View Transitions" entre páginas (Chrome/Edge 126+, Safari 18.2+):
      o menu lateral fica parado e só o conteúdo anima (sobe 40px e aparece em 280 ms).
      Ao voltar no histórico, a página que sai desce e some (200 ms), como no Ionic.
   2) Navegadores sem esse recurso (classe "sem-vt") e páginas abertas direto, sem navegar
      pelo menu (classe "carga-direta"): o CSS faz a mesma entrada, só na página nova.
   3) Pré-carrega a página do item do menu quando o mouse passa por cima, para o clique abrir na hora.
   ========================================================= */
(function () {
    'use strict';
    var html = document.documentElement;

    // Liga a transição entre páginas. Fica aqui, inline, e não no style.css, de propósito: o navegador
    // precisa saber do opt-in assim que a página nasce, sem esperar o CSS externo terminar de carregar.
    var optin = document.createElement('style');
    optin.textContent = '@view-transition{navigation:auto}';
    html.appendChild(optin);

    // 2) sem suporte -> animação de entrada simples feita só pelo CSS
    if (!('onpagereveal' in window)) html.classList.add('sem-vt');

    // As "etiquetas" view-transition-name só ficam ligadas DURANTE a transição (classe vt-ativa).
    // Assim elas não mudam o comportamento normal da página (position: fixed, empilhamento...).
    window.addEventListener('pageswap', function (e) {
        if (e.viewTransition) html.classList.add('vt-ativa');           // página que está saindo
    });

    window.addEventListener('pagereveal', function (e) {                 // página que está chegando
        if (!e.viewTransition) {                                          // abriu direto/atualizou: entrada simples
            html.classList.add('carga-direta');
            return;
        }
        html.classList.add('vt-ativa');
        try {
            var ativ = window.navigation && navigation.activation;       // voltou no histórico?
            if (ativ && ativ.navigationType === 'traverse' && ativ.from && ativ.entry
                && ativ.entry.index < ativ.from.index) {
                e.viewTransition.types.add('voltar');
            }
        } catch (_) { /* sem a Navigation API: segue como "ir para frente" */ }
        var fim = function () { html.classList.remove('vt-ativa'); };
        e.viewTransition.finished.then(fim, fim);
    });

    // página restaurada do cache do navegador (botão voltar): garante que não ficou nada ligado
    window.addEventListener('pageshow', function (e) {
        if (e.persisted) html.classList.remove('vt-ativa');
    });

    // 3) abre mais rápido: o navegador baixa a página quando o mouse passa no item do menu
    try {
        if (HTMLScriptElement.supports && HTMLScriptElement.supports('speculationrules')) {
            var regras = document.createElement('script');
            regras.type = 'speculationrules';
            regras.textContent = JSON.stringify({
                prefetch: [{ where: { selector_matches: 'a.nav-item[href$=".html"]' }, eagerness: 'moderate' }]
            });
            document.head.appendChild(regras);
        }
    } catch (_) { /* opcional */ }
})();
