## Improved

- Pull, push, clone, and Fork & Clone stay compact until an operation starts, then expand and show progress around the full outline while running. Translation retains the Download Button's layered and completion states. Error recovery uses a flat animated Agent button, while README Agent actions animate a folder, paper, and pencil.
- App catalog screenshots support automatic playback and manual navigation. README source, translation, and rewrite previews use card transitions.
- The Star action now uses an accent-color button with the GitHub mark, current count, state animation, and a single hover highlight sweep. Repository add, connectivity, and Agent tool controls also provide state-specific interaction feedback.
- README Agent can work directly with GitHub projects that have not been added locally and can be cancelled from the active control. Star updates now show progress around the button outline, and the sidebar scan control is larger.
- Translation now uses the README Agent control structure with a translation glyph and active status. Pull and push use the same sliding accent plate, directional motion, and outline progress as clone.
- Pull, push, clone, and Fork & Clone stop their activity motion and return to the default control after the core operation completes. Direction glyphs now follow a slower, continuous fade trajectory.
- The sidebar repository-add control and idle translation and README rewrite glyphs remain clearly distinguishable.
- Live refresh skips unchanged repository state, detail loading starts after the page switch frame, and glass-panel shadows no longer composite scrolling content.
- App catalog details can be translated by the Agent and cached for later switching. Screenshot galleries only show images supplied by the repository.
- Staging and unstaging update the workspace immediately and refresh only live Git state. Code previews reuse syntax analysis, while media loading no longer blocks diff content.
- Error reports preserve the complete original output and add the error code, a localized explanation, and targeted recovery for common Git, Agent, GitHub, file, and network failures.

## Fixed

- Local commits now remain visibly marked as not pushed until a push completes.
- Fixed invisible eyes in the Octocat loader and low outline contrast in the light glass theme.
- Sync presentation follows repository state, with warning treatment for unpushed commits and refresh errors kept as diagnostic help.
