# Sistema de Patrimônio — Sprint 3 (CRUD completo + Consultas)

## Banco de dados: ordem dos scripts (pasta `Banco/`)

Rode no MySQL 8, **nesta ordem** (cada script usa o anterior):

| # | Arquivo | O que cria |
|---|---|---|
| 1 | `inventario_escolar.sql` | estrutura (**apaga e recria** o banco `inventario_escolar`) |
| 2 | `functions.sql` | 11 functions (5 originais + 6 novas) |
| 3 | `procedures.sql` | 16 procedures (relatórios, consultas com parâmetro, regras de negócio, transferência e histórico) |
| 4 | `triggers.sql` | tabela `log_patrimonio` + 11 triggers (auditoria, validação, automação, padronização) |
| 5 | `views.sql` | 19 views (14 de consulta + 5 de patrimônio) |
| - | `demonstracao.sql` | roda cada objeto, para mostrar ao professor |

Os scripts 2 a 5 podem ser executados de novo sem problema (começam com `DROP ... IF EXISTS`).
Se o 1º arquivo já foi rodado antes, **não rode de novo** (ele zera os dados): rode só do 2 em diante.

## Como rodar

```bash
cd Backend
pip install -r requirements.txt
python app.py
```

Abra **http://127.0.0.1:5000**. Se der erro de conexão, abra **http://127.0.0.1:5000/health**:
ele mostra o motivo (senha errada, banco inexistente, MySQL desligado).

### Senha do MySQL

O app **sobe direto, sem perguntar nada**. A senha é lida (nesta ordem) de:

1. **Arquivo `Backend/.env`:** copie o `.env.example`, renomeie para `.env` e preencha `DB_PASSWORD=suasenha`.
   Também são aceitos os nomes `DB_PASS`, `DB_SENHA`, `MYSQL_PASSWORD`, `PASSWORD`..., em maiúsculo ou minúsculo.
   O app lê `.env.txt` também (o Windows cria esse nome sem você perceber quando as extensões estão ocultas).
2. **Arquivo `Backend/config_local.py`:** copie o `config_local.exemplo.py`, renomeie para `config_local.py` e troque a senha.
   É um arquivo Python comum, então não tem problema de extensão.

Nenhum deles vai para o GitHub (`.gitignore`). Ao subir, o app imprime uma linha dizendo se conectou ou o motivo
(e quais chaves leu do `.env`). Se der erro, abra **http://127.0.0.1:5000/health**.

## O que tem de novo

| Tela | O que faz |
|---|---|
| Inventário | filtros (nº, nome, categoria, status) + **Detalhes** (com as functions do banco) + **Editar** + Remover |
| Chamados | **Editar**, **Histórico** (linha do tempo) e nome do equipamento em cada chamado |
| Manutenções (nova) | CRUD completo, cards-resumo, filtro por situação, concluir com 1 clique |
| Usuários (nova) | CRUD completo (cadastrar, editar, trocar perfil/senha, remover) |
| Consultas (nova) | 29 consultas (simples, intermediárias, complexas e resumos) com filtros, tabela, gráfico, **CSV** e **PDF**. O SQL de cada uma fica no banco (views/procedures), não na tela |
| Relatórios | botão Exportar PDF agora funciona (impressão do navegador → "Salvar como PDF") |

### Regras de negócio implementadas
- Criar manutenção sem data de fim → equipamento passa para **Em manutenção** (triggers `trg_manutencao_*` + `sp_sincronizar_equipamento`).
- Concluir/remover a última manutenção aberta do equipamento → ele volta para **Disponível**.
- Usuário com chamados não pode ser removido (`sp_remover_usuario` + `fn_total_vinculos_usuario`); ninguém remove a si mesmo.
- Mudar o status do chamado é uma transação no banco (`sp_alterar_status_chamado`): troca o status e grava o histórico juntos; a trigger `trg_chamado_data_fechamento` preenche/limpa `data_fechamento`.
- E-mail do usuário é salvo em minúsculas e sem espaços (trigger `trg_usuario_normaliza_*`).
- Promover a administrador: `sp_promover_admin`. Permissão de administrador: `fn_usuario_eh_admin`.
- Status do chamado só muda pelos botões (gera histórico); o modal "Editar" não mexe no status.
- Usuário que já tem chamados/histórico não é apagado: use Editar → Situação: Inativo (ele deixa de conseguir entrar). O login registra `ultimo_login`.
- A data de fechamento do chamado usa a coluna `data_fechamento` do seu banco (não é criada nenhuma coluna nova).

## Onde está cada coisa
- `Banco/*.sql` — **todo o SQL do projeto** (functions, views, procedures, triggers). As consultas e regras de negócio vivem aqui.
- `Backend/consultas.py` — só o catálogo das consultas (título, filtros, gráfico e qual view/procedure chamar). Não tem SQL.
- `Backend/app.py` — rotas; para as consultas faz `SELECT * FROM vw_...` ou `CALL sp_...`. Ao subir, avisa se faltar algum objeto do banco.
- `Frontend/modulos.js` — modal, Manutenções, Usuários, Consultas (mostra só o resultado).

## Observações
- As consultas **A3, A5 e A6** (views com CTE/funções de janela) exigem **MySQL 8.0+**, assim como a estrutura do banco (CHECK, DEFAULT (CURRENT_DATE)).
- Os parâmetros das consultas vão como argumentos de `CALL` (nada de concatenar texto), então não há SQL Injection.
- Erros de regra criados no banco com `SIGNAL SQLSTATE '45xxx'` aparecem na tela com a mensagem do banco (45404 = não encontrado, 45409 = conflito).

## Cadastro: e-mail e senha

- **E-mail:** qualquer endereço no formato `algo@dominio.terminação` é aceito (pessoal, institucional ou de prefeitura), por exemplo `ana@gmail.com`, `joao@ifrj.edu.br`, `maria@campos.rj.gov.br`. A regra vale no front-end e no backend (`validar_email` em `app.py`).
- **Senha:** todo campo de senha tem o botão de olho para mostrar/ocultar. No cadastro (e em "Novo usuário"/"Editar usuário") é preciso digitar a senha duas vezes; o sistema avisa na hora se as duas são iguais.


## Perfis: administrador x usuário comum

| | Usuário comum | Administrador |
|---|---|---|
| Dashboard, Inventário, Cadastrar, Chamados, Manutenções, Consultas, Relatórios | ✅ | ✅ |
| **Usuários** (cadastrar, editar, trocar perfil, remover) | ❌ (o link some e a página volta para o Dashboard) | ✅ |

A restrição também vale no backend: as rotas `/usuarios` e `/admin` respondem **401** sem login e **403** para usuário comum.
O front envia o id de quem está logado no cabeçalho `X-Usuario-Id` e o backend confere o perfil no banco.

**Como virar administrador pela primeira vez** (só no MySQL, porque só um admin consegue promover outro pela tela):

```sql
UPDATE usuario SET tipo_usuario = 'admin' WHERE email = 'seu@email.com';

INSERT IGNORE INTO admin (id_admin, nivel_acesso, permissoes)
SELECT id_usuario, 5, 'total' FROM usuario WHERE email = 'seu@email.com';
```

Depois **saia e entre de novo** no sistema (o perfil é lido no login).

## Menu lateral (ordem)

Dashboard → Inventário → Cadastrar → Chamados → Manutenções → Consultas → Relatórios → Usuários (só admin).
