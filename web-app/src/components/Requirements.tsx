export function Requirements() {
  return (
    <section>
      <h2>Requirements</h2>
      <dl className="reqs">
        <div className="req">
          <dt>macOS</dt>
          <dd>
            <b>macOS 14+</b> (Apple Silicon &amp; Intel).
          </dd>
        </div>
        <div className="req">
          <dt>Claude Code</dt>
          <dd>
            Sessions are tracked through Claude Code's own hooks, with a one-time guided setup on
            first launch.
          </dd>
        </div>
        <div className="req">
          <dt>Accessibility</dt>
          <dd>
            <b>Optional.</b> Needed only for window-precise click-to-focus and replying from the
            island; without it both degrade gracefully to focusing the app.
          </dd>
        </div>
      </dl>
    </section>
  );
}
