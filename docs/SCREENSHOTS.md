# Screenshot Checklist for Parts 2 and 3

Take screenshots in this order:

## Part 2 — Governor & Timelock

1. `npx hardhat compile` successful output.
2. `npx hardhat test` showing passed DAO tests.
3. `localDemo.js` output showing deployed contracts.
4. Delegation output showing voting power.
5. Proposal ID after `Box.store(42)` proposal.
6. Proposal state `Active`.
7. Vote results: Against / For / Abstain.
8. Proposal state `Succeeded`.
9. Proposal state `Queued`.
10. Proposal state `Executed`.

## Part 3 — Treasury & Controlled Contract

1. `Treasury.sol` code screenshot.
2. `Box.sol` code screenshot.
3. Test result for ERC-20 transfer from Treasury.
4. Test result for ETH transfer from Treasury.
5. Final demo output: `Box value: 42`.
