# Project instructions

- **Handbook rule:** every change to application behaviour (features, roles, menus, workflows, data import/export, onboarding/offboarding, security or privacy) must update `docs\HANDBOOK.md` in the same commit: the relevant section, the role matrix if access changed, and a new row in the Change log. Then run `python docs\build_handbook.py` to regenerate `docs\Flatsphere_Handbook.docx` and commit both files. Do not skip this for small changes; if nothing user-facing changed, say so in the commit message.
- Windows/PowerShell: chain with `;`, not `&&`. Run the Supabase CLI as `npm exec --yes --package supabase -- supabase <args>`.
- Commits include the trailer `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
- Database changes go in a new timestamped file under `supabase\migrations` (never edit applied ones) and are applied with `supabase db push --linked --yes`.
- Keep credit use low: targeted `dart analyze <files>` and `flutter test test\widget_test.dart test\responsive_test.dart`, not full runs.
