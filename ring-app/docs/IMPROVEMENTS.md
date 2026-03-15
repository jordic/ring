# Propostes de millora per a Ring App

1. Unificar models UI/CLI de scopes.
Ara hi ha duplicació entre `ring-app` i `cli` (providers/scopes). Un sol source of truth evita bugs i desalineacions.

2. Persistir "state de navegació" del popover.
Recordar l’últim provider o vista oberta (optional) millora fluxos repetitius.

3. Buscar i filtrar providers.
Un `search` al header accelera molt quan afegiu més integracions.

4. Historial d’activitat/auditoria local.
Mostrar “últim refresh”, “últim authorize”, errors OAuth recents per provider.

5. Health checks per provider.
Botó “Test connection” que fa una crida mínima API i retorna estat real, no només “token present”.

6. Gestió de scopes més intel·ligent.
Mostrar diferència `granted vs selected`, i “recommended scopes” per casos d’ús.

7. Errors OAuth més accionables.
Mapejar errors comuns (redirect mismatch, invalid_client, scope invalid) amb suggeriments concrets.

8. Refresh automàtic i silenciós.
Task periòdica per refrescar tokens propers a expirar i notificar només si falla.

9. UX de seguretat.
Indicador clar de secrets presents (client secret, refresh token), opció “revoke + remove local”.

10. Integració directa amb Google/GitHub test actions.
Exemples “Read first Gmail subject”, “List latest repos” dins UI per validar setup de punta a punta.

11. Export/import xifrat de configuració.
Per migrar màquines sense tornar a configurar tot manualment.

12. Tests E2E del flux menubar.
Automatitzar tests de `setup -> authorize -> scopes -> logout` per evitar regressions d’interacció.

13. Telemetria local opcional (privacy-first).
Només events locals per detectar fricció UX (temps per completar setup, passos abandonats).

14. Accessibilitat.
Millorar focus order, VoiceOver labels i contrast en badges/estats.

15. Gestió de credencials millorada.
A `Credentials`: editar/eliminar, tags, i còpia ràpida (username/password/TOTP) amb timeout visual.
