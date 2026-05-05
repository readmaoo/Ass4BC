import Header from "./components/Header";
import Delegation from "./components/Delegation";
import Governance from "./components/Governance";
import Active from "./components/Active";
import "./App.css"; 
import { useState } from "react";
import Proposal from "./components/Proposal";

export default function App() {
  const[active,setActive] = useState(false)
  function handleClick(){
    setActive(true)
  }
  return (
    <div className="app">
      <Header onActive = {handleClick} />
      <div className="main">
        <aside className="sidebar">
          <Delegation active={active}/>
          <Governance />
        </aside>
        <section className="proposals">
          <Active />
          <Proposal active={active}/>
        </section>
      </div>
    </div>
  );
}