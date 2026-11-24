# Product direction (candidate modes — no decisions locked)

Three archetypes emerged from brainstorming. Slop could lean into one or blend.

## Mode A — Knowledge worker ("complex reasoning")
- Complex reasoning, multi-step assignments, deliverables
- Software development, presentations, research, file manipulation
- Speciality: hard decisions, exploring ideas, learning

## Mode B — Conversational companion ("emotional intelligence")
- Natural, supportive conversation; conversational continuity
- Voice interaction (candidate: llama-tts)
- Speciality: emotional intelligence, practicing conversations

## Mode C — Personal context agent ("device integration")
- Recognises what's on screen, retrieves info from messages/emails
- Manipulates documents, analyses spreadsheets, summarises meetings
- Delegates work to agents; privacy-oriented, local-first
- Speciality: personal context + device integration

## Common thread
Local-first (llama.cpp), screen-aware (UIA + vision), human-in-the-loop for writes,
allowlisted the user functions. All three modes share the same core; they differ in
emphasis and default prompts.

## Open
- Which mode is primary for v1? (recommend starting with C (screen context) since the
  architecture already optimises for it, then layer A/B)
- Voice in v1 or later?
