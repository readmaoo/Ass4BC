const fs = require("fs");
const { ethers } = require("hardhat");

async function main() {
  const [deployer, fallbackCommunity, fallbackLiquidity] = await ethers.getSigners();

  const MIN_DELAY = 2 * 24 * 60 * 60;
  const VOTING_DELAY_BLOCKS = 7200;
  const VOTING_PERIOD_BLOCKS = 50400;
  const PROPOSAL_THRESHOLD = ethers.parseEther("10000");

  const teamWallet = process.env.TEAM_WALLET || deployer.address;
  const communityWallet = process.env.COMMUNITY_WALLET || fallbackCommunity.address;
  const liquidityWallet = process.env.LIQUIDITY_WALLET || fallbackLiquidity.address;

  console.log("Deploying with account:", deployer.address);
  console.log("Team wallet:", teamWallet);
  console.log("Community wallet:", communityWallet);
  console.log("Liquidity wallet:", liquidityWallet);

  const TimelockController = await ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(MIN_DELAY, [], [], deployer.address);
  await timelock.waitForDeployment();
  console.log("TimelockController:", timelock.target);

  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(timelock.target);
  await treasury.waitForDeployment();
  console.log("Treasury:", treasury.target);

  const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
  const token = await GovernanceToken.deploy(teamWallet, treasury.target, communityWallet, liquidityWallet);
  await token.waitForDeployment();
  console.log("GovernanceToken:", token.target);

  const MyGovernor = await ethers.getContractFactory("MyGovernor");
  const governor = await MyGovernor.deploy(
    token.target,
    timelock.target,
    VOTING_DELAY_BLOCKS,
    VOTING_PERIOD_BLOCKS,
    PROPOSAL_THRESHOLD
  );
  await governor.waitForDeployment();
  console.log("MyGovernor:", governor.target);

  const Box = await ethers.getContractFactory("Box");
  const box = await Box.deploy(timelock.target);
  await box.waitForDeployment();
  console.log("Box:", box.target);

  const FeeSettings = await ethers.getContractFactory("FeeSettings");
  const feeSettings = await FeeSettings.deploy(timelock.target, 100);
  await feeSettings.waitForDeployment();
  console.log("FeeSettings:", feeSettings.target);

  const proposerRole = await timelock.PROPOSER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();
  const cancellerRole = await timelock.CANCELLER_ROLE();
  const adminRole = await timelock.DEFAULT_ADMIN_ROLE();

  await (await timelock.grantRole(proposerRole, governor.target)).wait();
  await (await timelock.grantRole(executorRole, ethers.ZeroAddress)).wait();
  await (await timelock.grantRole(cancellerRole, governor.target)).wait();
  await (await timelock.revokeRole(adminRole, deployer.address)).wait();

  console.log("Timelock roles configured:");
  console.log("- Governor is proposer");
  console.log("- Everyone can execute queued actions");
  console.log("- Governor is canceller");
  console.log("- Deployer admin role revoked");

  const addresses = {
    network: (await ethers.provider.getNetwork()).name,
    chainId: Number((await ethers.provider.getNetwork()).chainId),
    deployer: deployer.address,
    token: token.target,
    governor: governor.target,
    timelock: timelock.target,
    treasury: treasury.target,
    box: box.target,
    feeSettings: feeSettings.target,
    votingDelayBlocks: VOTING_DELAY_BLOCKS,
    votingPeriodBlocks: VOTING_PERIOD_BLOCKS,
    proposalThreshold: PROPOSAL_THRESHOLD.toString(),
    quorum: "4%",
    timelockDelaySeconds: MIN_DELAY
  };

  fs.writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
  console.log("Addresses saved to deployed-addresses.json");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
