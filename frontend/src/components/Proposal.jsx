import "../styles/Proposal.css"

export default function Proposal({active}) {
    return (
        <div className="proposal-item">
            <h3>Proposal</h3>
            <div className="proposal-info">
                <p>Title:</p>
                <p>Status:</p>
                <p>Time Left:</p>
            </div>

            <div className="proposal-actions">
                <button className= {active ? "vote-btn1" :"vote-btn"}>FOR </button>
                <button className= {active ? "vote-btn1" :"vote-btn"}>AGAINST</button>
                <button className= {active ? "vote-btn1" :"vote-btn"}>ABSTAIN</button>
            </div>

            <p className="proposal-results">
                Current Results: For:  Against: 
            </p>
        </div>
    )
}