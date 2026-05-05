const { ethers, network } = require("hardhat");
const { time, mine } = require("@nomicfoundation/hardhat-network-helpers");

const ProposalState = {
  Pending: 0,
  Active: 1,
  Canceled: 2,
  Defeated: 3,
  Succeeded: 4,
  Queued: 5,
  Expired: 6,
  Executed: 7
};

async function getProposalId(tx, governor) {
  const receipt = await tx.wait();
  for (const log of receipt.logs) {
    try {
      const parsed = governor.interface.parseLog(log);
      if (parsed && parsed.name === "ProposalCreated") {
        return parsed.args.proposalId;
      }
    } catch (_) {}
  }
  throw new Error("ProposalCreated event not found");
}

async function main() {
  if (network.name !== "hardhat") {
    throw new Error("Run this demo with: npx hardhat run scripts/localDemo.js");
  }

  const [deployer, voter1, voter2, recipient] = await ethers.getSigners();

  const MIN_DELAY = 60;
  const VOTING_DELAY_BLOCKS = 1;
  const VOTING_PERIOD_BLOCKS = 5;
  const PROPOSAL_THRESHOLD = ethers.parseEther("10000");

  console.log("STEP 1 — Deploy Timelock, Treasury, Token, Governor, Box");

  const TimelockController = await ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(MIN_DELAY, [], [], deployer.address);
  await timelock.waitForDeployment();

  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(timelock.target);
  await treasury.waitForDeployment();

  const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
  const token = await GovernanceToken.deploy(deployer.address, treasury.target, voter1.address, voter2.address);
  await token.waitForDeployment();

  const MyGovernor = await ethers.getContractFactory("MyGovernor");
  const governor = await MyGovernor.deploy(token.target, timelock.target, VOTING_DELAY_BLOCKS, VOTING_PERIOD_BLOCKS, PROPOSAL_THRESHOLD);
  await governor.waitForDeployment();

  const Box = await ethers.getContractFactory("Box");
  const box = await Box.deploy(timelock.target);
  await box.waitForDeployment();

  const proposerRole = await timelock.PROPOSER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();
  const cancellerRole = await timelock.CANCELLER_ROLE();
  const adminRole = await timelock.DEFAULT_ADMIN_ROLE();

  await (await timelock.grantRole(proposerRole, governor.target)).wait();
  await (await timelock.grantRole(executorRole, ethers.ZeroAddress)).wait();
  await (await timelock.grantRole(cancellerRole, governor.target)).wait();
  await (await timelock.revokeRole(adminRole, deployer.address)).wait();

  console.log("Token:", token.target);
  console.log("Governor:", governor.target);
  console.log("Timelock:", timelock.target);
  console.log("Treasury:", treasury.target);
  console.log("Box:", box.target);

  console.log("\nSTEP 2 — Delegate voting power");
  await (await token.connect(deployer).delegate(deployer.address)).wait();
  await (await token.connect(voter1).delegate(voter1.address)).wait();
  await (await token.connect(voter2).delegate(voter2.address)).wait();
  await mine(1);
  console.log("Deployer votes:", ethers.formatEther(await token.getVotes(deployer.address)));
  console.log("Voter1 votes:", ethers.formatEther(await token.getVotes(voter1.address)));

  console.log("\nSTEP 3 — Create proposal: Box.store(42)");
  const calldata = box.interface.encodeFunctionData("store", [42]);
  const description = "Proposal #1: store value 42 in Box";
  const proposalTx = await governor.connect(deployer).propose([box.target], [0], [calldata], description);
  const proposalId = await getProposalId(proposalTx, governor);
  console.log("Proposal ID:", proposalId.toString());
  console.log("State after propose:", Number(await governor.state(proposalId)), "Pending");

  console.log("\nSTEP 4 — Move to active voting period");
  await mine(VOTING_DELAY_BLOCKS + 1);
  console.log("State:", Number(await governor.state(proposalId)), "Active");

  console.log("\nSTEP 5 — Cast votes: For / Abstain");
  await (await governor.connect(deployer).castVote(proposalId, 1)).wait();
  await (await governor.connect(voter1).castVote(proposalId, 2)).wait();
  const votes = await governor.proposalVotes(proposalId);
  console.log("Against:", ethers.formatEther(votes.againstVotes));
  console.log("For:", ethers.formatEther(votes.forVotes));
  console.log("Abstain:", ethers.formatEther(votes.abstainVotes));

  console.log("\nSTEP 6 — End voting period");
  await mine(VOTING_PERIOD_BLOCKS + 1);
  console.log("State:", Number(await governor.state(proposalId)), "Succeeded");

  console.log("\nSTEP 7 — Queue proposal in Timelock");
  const descriptionHash = ethers.id(description);
  await (await governor.queue([box.target], [0], [calldata], descriptionHash)).wait();
  console.log("State:", Number(await governor.state(proposalId)), "Queued");

  console.log("\nSTEP 8 — Wait Timelock delay and execute");
  await time.increase(MIN_DELAY + 1);
  await mine(1);
  await (await governor.execute([box.target], [0], [calldata], descriptionHash)).wait();
  console.log("State:", Number(await governor.state(proposalId)), "Executed");
  console.log("Box value:", (await box.retrieve()).toString());

  console.log("\nDEMO FINISHED — full lifecycle: propose → vote → queue → execute → verify");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
