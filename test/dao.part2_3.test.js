const { expect } = require("chai");
const { ethers } = require("hardhat");
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

async function deployDaoFixture() {
  const [owner, voter1, voter2, outsider, recipient] = await ethers.getSigners();

  const MIN_DELAY = 60;
  const VOTING_DELAY = 1;
  const VOTING_PERIOD = 5;
  const PROPOSAL_THRESHOLD = ethers.parseEther("10000");

  const TimelockController = await ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(MIN_DELAY, [], [], owner.address);
  await timelock.waitForDeployment();

  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(timelock.target);
  await treasury.waitForDeployment();

  const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
  const token = await GovernanceToken.deploy(owner.address, treasury.target, voter1.address, voter2.address);
  await token.waitForDeployment();

  const MyGovernor = await ethers.getContractFactory("MyGovernor");
  const governor = await MyGovernor.deploy(token.target, timelock.target, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD);
  await governor.waitForDeployment();

  const Box = await ethers.getContractFactory("Box");
  const box = await Box.deploy(timelock.target);
  await box.waitForDeployment();

  const FeeSettings = await ethers.getContractFactory("FeeSettings");
  const feeSettings = await FeeSettings.deploy(timelock.target, 100);
  await feeSettings.waitForDeployment();

  const proposerRole = await timelock.PROPOSER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();
  const cancellerRole = await timelock.CANCELLER_ROLE();
  const adminRole = await timelock.DEFAULT_ADMIN_ROLE();

  await (await timelock.grantRole(proposerRole, governor.target)).wait();
  await (await timelock.grantRole(executorRole, ethers.ZeroAddress)).wait();
  await (await timelock.grantRole(cancellerRole, governor.target)).wait();
  await (await timelock.revokeRole(adminRole, owner.address)).wait();

  await (await token.connect(owner).delegate(owner.address)).wait();
  await (await token.connect(voter1).delegate(voter1.address)).wait();
  await (await token.connect(voter2).delegate(voter2.address)).wait();
  await mine(1);

  return {
    owner,
    voter1,
    voter2,
    outsider,
    recipient,
    MIN_DELAY,
    VOTING_DELAY,
    VOTING_PERIOD,
    PROPOSAL_THRESHOLD,
    token,
    timelock,
    governor,
    treasury,
    box,
    feeSettings
  };
}

async function propose(governor, proposer, target, calldata, description, value = 0) {
  const tx = await governor.connect(proposer).propose([target], [value], [calldata], description);
  const proposalId = await getProposalId(tx, governor);
  return { proposalId, descriptionHash: ethers.id(description) };
}

async function passProposal({ governor, voter, proposalId, VOTING_DELAY, VOTING_PERIOD }) {
  await mine(VOTING_DELAY + 1);
  await (await governor.connect(voter).castVote(proposalId, 1)).wait();
  await mine(VOTING_PERIOD + 1);
}

async function queueAndExecute({ governor, MIN_DELAY, target, calldata, descriptionHash, value = 0 }) {
  await (await governor.queue([target], [value], [calldata], descriptionHash)).wait();
  await time.increase(MIN_DELAY + 1);
  await mine(1);
  await (await governor.execute([target], [value], [calldata], descriptionHash, { value })).wait();
}

describe("Assignment 4 — Parts 2 and 3 DAO Governance", function () {
  it("deploys Governor with correct voting configuration", async function () {
    const { governor, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD } = await deployDaoFixture();

    expect(await governor.name()).to.equal("FarmersMarketGovernor");
    expect(await governor.votingDelay()).to.equal(VOTING_DELAY);
    expect(await governor.votingPeriod()).to.equal(VOTING_PERIOD);
    expect(await governor.proposalThreshold()).to.equal(PROPOSAL_THRESHOLD);
  });

  it("sets quorum to 4% of total supply", async function () {
    const { governor } = await deployDaoFixture();
    const latestBlock = await ethers.provider.getBlockNumber();

    expect(await governor.quorum(latestBlock - 1)).to.equal(ethers.parseEther("40000"));
  });

  it("connects Governor to TimelockController", async function () {
    const { governor, timelock } = await deployDaoFixture();

    expect(await governor.timelock()).to.equal(timelock.target);
  });

  it("makes the Governor the sole proposer in the Timelock", async function () {
    const { owner, governor, timelock } = await deployDaoFixture();

    const proposerRole = await timelock.PROPOSER_ROLE();
    const adminRole = await timelock.DEFAULT_ADMIN_ROLE();

    expect(await timelock.hasRole(proposerRole, governor.target)).to.equal(true);
    expect(await timelock.hasRole(adminRole, owner.address)).to.equal(false);
  });

  it("allows everyone to execute queued Timelock actions", async function () {
    const { timelock } = await deployDaoFixture();

    const executorRole = await timelock.EXECUTOR_ROLE();
    expect(await timelock.hasRole(executorRole, ethers.ZeroAddress)).to.equal(true);
  });

  it("sets Timelock as the owner of Treasury, Box, and FeeSettings", async function () {
    const { timelock, treasury, box, feeSettings } = await deployDaoFixture();

    expect(await treasury.owner()).to.equal(timelock.target);
    expect(await box.owner()).to.equal(timelock.target);
    expect(await feeSettings.owner()).to.equal(timelock.target);
  });

  it("runs full lifecycle for Box.store(42): propose → vote → queue → execute → verify", async function () {
    const fixture = await deployDaoFixture();
    const { owner, governor, box } = fixture;

    const calldata = box.interface.encodeFunctionData("store", [42]);
    const description = "Store 42 in Box";
    const proposal = await propose(governor, owner, box.target, calldata, description);

    expect(await governor.state(proposal.proposalId)).to.equal(ProposalState.Pending);
    await passProposal({ ...fixture, voter: owner, proposalId: proposal.proposalId });
    expect(await governor.state(proposal.proposalId)).to.equal(ProposalState.Succeeded);

    await queueAndExecute({ ...fixture, target: box.target, calldata, descriptionHash: proposal.descriptionHash });

    expect(await governor.state(proposal.proposalId)).to.equal(ProposalState.Executed);
    expect(await box.retrieve()).to.equal(42);
  });

  it("transfers ERC-20 tokens from Treasury via governance", async function () {
    const fixture = await deployDaoFixture();
    const { owner, recipient, token, treasury, governor } = fixture;

    const amount = ethers.parseEther("100");
    const calldata = treasury.interface.encodeFunctionData("releaseToken", [token.target, recipient.address, amount]);
    const description = "Transfer 100 FMGT from Treasury to recipient";
    const proposal = await propose(governor, owner, treasury.target, calldata, description);

    await passProposal({ ...fixture, voter: owner, proposalId: proposal.proposalId });
    await queueAndExecute({ ...fixture, target: treasury.target, calldata, descriptionHash: proposal.descriptionHash });

    expect(await token.balanceOf(recipient.address)).to.equal(amount);
  });

  it("transfers ETH from Treasury via governance", async function () {
    const fixture = await deployDaoFixture();
    const { owner, recipient, treasury, governor } = fixture;

    await owner.sendTransaction({ to: treasury.target, value: ethers.parseEther("1") });

    const amount = ethers.parseEther("0.2");
    const beforeBalance = await ethers.provider.getBalance(recipient.address);
    const calldata = treasury.interface.encodeFunctionData("releaseETH", [recipient.address, amount]);
    const description = "Transfer 0.2 ETH from Treasury to recipient";
    const proposal = await propose(governor, owner, treasury.target, calldata, description);

    await passProposal({ ...fixture, voter: owner, proposalId: proposal.proposalId });
    await queueAndExecute({ ...fixture, target: treasury.target, calldata, descriptionHash: proposal.descriptionHash });

    const afterBalance = await ethers.provider.getBalance(recipient.address);
    expect(afterBalance - beforeBalance).to.equal(amount);
  });

  it("changes a parameter in another contract through governance", async function () {
    const fixture = await deployDaoFixture();
    const { owner, feeSettings, governor } = fixture;

    const calldata = feeSettings.interface.encodeFunctionData("setFeeBps", [250]);
    const description = "Change protocol fee to 2.5 percent";
    const proposal = await propose(governor, owner, feeSettings.target, calldata, description);

    await passProposal({ ...fixture, voter: owner, proposalId: proposal.proposalId });
    await queueAndExecute({ ...fixture, target: feeSettings.target, calldata, descriptionHash: proposal.descriptionHash });

    expect(await feeSettings.feeBps()).to.equal(250);
  });

  it("delegatee votes using delegated voting power", async function () {
    const fixture = await deployDaoFixture();
    const { owner, voter1, token, governor, box } = fixture;

    await (await token.connect(voter1).delegate(owner.address)).wait();
    await mine(1);

    const calldata = box.interface.encodeFunctionData("store", [7]);
    const description = "Store 7 in Box with delegated votes";
    const proposal = await propose(governor, owner, box.target, calldata, description);

    await mine(fixture.VOTING_DELAY + 1);
    await (await governor.connect(owner).castVote(proposal.proposalId, 1)).wait();

    const votes = await governor.proposalVotes(proposal.proposalId);
    expect(votes.forVotes).to.equal(ethers.parseEther("600000"));
  });

  it("defeats proposal when quorum is not met", async function () {
    const fixture = await deployDaoFixture();
    const { owner, governor, box, VOTING_DELAY, VOTING_PERIOD } = fixture;

    const calldata = box.interface.encodeFunctionData("store", [99]);
    const description = "Proposal with no quorum";
    const proposal = await propose(governor, owner, box.target, calldata, description);

    await mine(VOTING_DELAY + 1);
    await mine(VOTING_PERIOD + 1);

    expect(await governor.state(proposal.proposalId)).to.equal(ProposalState.Defeated);
  });

  it("defeats proposal when against votes win", async function () {
    const fixture = await deployDaoFixture();
    const { owner, voter1, governor, box, VOTING_DELAY, VOTING_PERIOD } = fixture;

    const calldata = box.interface.encodeFunctionData("store", [123]);
    const description = "Proposal defeated by against votes";
    const proposal = await propose(governor, owner, box.target, calldata, description);

    await mine(VOTING_DELAY + 1);
    await (await governor.connect(owner).castVote(proposal.proposalId, 0)).wait();
    await (await governor.connect(voter1).castVote(proposal.proposalId, 1)).wait();
    await mine(VOTING_PERIOD + 1);

    expect(await governor.state(proposal.proposalId)).to.equal(ProposalState.Defeated);
  });

  it("blocks direct Box.store calls from non-Timelock accounts", async function () {
    const { owner, box } = await deployDaoFixture();

    await expect(box.connect(owner).store(1)).to.be.revertedWithCustomError(box, "OwnableUnauthorizedAccount");
  });

  it("blocks direct Treasury withdrawals from non-Timelock accounts", async function () {
    const { owner, recipient, treasury } = await deployDaoFixture();

    await owner.sendTransaction({ to: treasury.target, value: ethers.parseEther("1") });
    await expect(treasury.connect(owner).releaseETH(recipient.address, ethers.parseEther("0.1"))).to.be.revertedWithCustomError(
      treasury,
      "OwnableUnauthorizedAccount"
    );
  });
    async function deployUpgradeableBox(timelock) {
    const UpgradeableBoxV1 = await ethers.getContractFactory("UpgradeableBoxV1");
    const boxV1Implementation = await UpgradeableBoxV1.deploy();
    await boxV1Implementation.waitForDeployment();

    const initData = boxV1Implementation.interface.encodeFunctionData("initialize", [timelock.target]);

    const UpgradeableBoxProxy = await ethers.getContractFactory("UpgradeableBoxProxy");

    const proxy = await UpgradeableBoxProxy.deploy(boxV1Implementation.target, initData);
    await proxy.waitForDeployment();

    const upgradeableBox = await ethers.getContractAt("UpgradeableBoxV1", proxy.target);

    return { boxV1Implementation, proxy, upgradeableBox };
  }

  it("upgrades a controlled contract only through Timelock governance", async function () {
    const fixture = await deployDaoFixture();
    const { owner, governor, timelock } = fixture;

    const { upgradeableBox } = await deployUpgradeableBox(timelock);

    expect(await upgradeableBox.owner()).to.equal(timelock.target);
    expect(await upgradeableBox.version()).to.equal("V1");

    const UpgradeableBoxV2 = await ethers.getContractFactory("UpgradeableBoxV2");
    const boxV2Implementation = await UpgradeableBoxV2.deploy();
    await boxV2Implementation.waitForDeployment();

    const calldata = upgradeableBox.interface.encodeFunctionData("upgradeTo", [boxV2Implementation.target]);
    const description = "Upgrade controlled Box proxy from V1 to V2";

    const proposal = await propose(governor, owner, upgradeableBox.target, calldata, description);

    await passProposal({ ...fixture, voter: owner, proposalId: proposal.proposalId });

    await queueAndExecute({
      ...fixture,
      target: upgradeableBox.target,
      calldata,
      descriptionHash: proposal.descriptionHash,
    });

    const upgradedBox = await ethers.getContractAt("UpgradeableBoxV2", upgradeableBox.target);

    expect(await upgradedBox.version()).to.equal("V2");
  });

  it("blocks direct contract upgrades from non-Timelock accounts", async function () {
    const { owner, timelock } = await deployDaoFixture();

    const { upgradeableBox } = await deployUpgradeableBox(timelock);

    const UpgradeableBoxV2 = await ethers.getContractFactory("UpgradeableBoxV2");
    const boxV2Implementation = await UpgradeableBoxV2.deploy();
    await boxV2Implementation.waitForDeployment();

    await expect(
      upgradeableBox.connect(owner).upgradeTo(boxV2Implementation.target)
    ).to.be.revertedWith("Only owner");
  });
});
