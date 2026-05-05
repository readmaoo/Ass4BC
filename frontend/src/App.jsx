import Header from "./components/Header";
import Delegation from "./components/Delegation";
import Governance from "./components/Governance";
import Active from "./components/Active";
import "./App.css"; 

export default function App() {
  return (
    <div className="app">
      <Header />
      <div className="main">
        <aside className="sidebar">
          <Delegation />
          <Governance />
        </aside>
        <section className="proposals">
          <Active />
        </section>
      </div>
    </div>
  );
}