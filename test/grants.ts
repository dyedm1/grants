import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockProvider } from "ethereum-waffle";
import { ERC20, ERC20__factory, Grants, Grants__factory } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {BigNumber} from "ethers";

const { provider } = waffle;
async function increaseBlockTimestamp(provider: MockProvider, time: number) {
  await provider.send("evm_increaseTime", [time]);
  await provider.send("evm_mine", []);
}

describe("grants", function () {
  let token: ERC20;
  let grants: Grants;
  const [wallet] = provider.getWallets();
  let signers: SignerWithAddress[];
  let spender: ERC20;
  let granters: Grants[] = [];
  // resets state of token - required before some tests
  async function fixture() {
    signers = await ethers.getSigners();
    const deployer = new ERC20__factory(signers[0]);
    token = await deployer.deploy("token", "TKN");
    await token.mint(signers[0].address, ethers.utils.parseEther("1000"));
    spender = token.connect(signers[1]);
    const deployer2 = new Grants__factory(signers[0]);
    grants = await deployer2.deploy();
    for(let i=0; i<5; i++) {
      granters.push(await grants.connect(signers[i]));
    }


  }
  before(async function () {
    await fixture();

  });
  //could have had an add/remove member function but I'm falling asleep and this contract is pretty big already
  describe("Org management", async () => {
    it("Create Org", async () => {
      await grants.createOrg([signers[0].address,signers[1].address, signers[2].address], 1);
      await grants.createOrg([signers[0].address,signers[1].address, signers[2].address], 3);
      expect(await grants.members(1,signers[2].address)).to.be.true;
      expect(await grants.members(2,signers[2].address)).to.be.true;
    });
    describe("Wallet management", async () => {
      it("Deposit tokens", async () => {
        await token.approve(grants.address, ethers.utils.parseEther("1000"));
        await grants.deposit(1, token.address, ethers.utils.parseEther("100"));
        await grants.deposit(2, token.address, ethers.utils.parseEther("100"));
        expect(await grants.balances(1, token.address)).to.be.equal(ethers.utils.parseEther("100"));
        expect(await grants.balances(2, token.address)).to.be.equal(ethers.utils.parseEther("100"));

      });
      it("Withdraw tokens(1 confirmation org, instant)", async () => {
        await grants.proposeWithdrawal(1, signers[0].address, token.address, ethers.utils.parseEther("1"));
        expect(await token.balanceOf(signers[0].address)).to.be.equal(ethers.utils.parseEther("801"));
      });
      it("Propose withdrawal with insufficient funds", async () => {
        const tx = grants.proposeWithdrawal(1, signers[0].address, token.address, ethers.utils.parseEther("1000"));
        await expect(tx).to.be.revertedWith("Insufficient balance for withdrawal")
      });
      it("Propose withdrawal", async () => {
        await grants.proposeWithdrawal(2, signers[0].address, token.address, ethers.utils.parseEther("1"));
        await grants.proposeWithdrawal(2, signers[0].address, token.address, ethers.utils.parseEther("100"));
        //console.log(await grants.withdrawals(2, 1,))
        expect((await grants.withdrawals(2, 1,)).destination).to.be.equal(signers[0].address);
      });
      it("Confirm withdrawal", async () => {
        await granters[1].confirmWithdrawal(2, 1);
        await granters[1].confirmWithdrawal(2, 2);
        expect((await grants.withdrawals(2,1)).confirmations[0]).to.be.equal(2);
      });
      it("Withdraw tokens(3 confirmation org)", async () => {
        await granters[2].confirmWithdrawal(2, 1);
        expect(await token.balanceOf(signers[0].address)).to.be.equal(ethers.utils.parseEther("802"));
      });
        it("Withdraw tokens with insufficent funds", async () => {
          const tx = granters[2].confirmWithdrawal(2,2);
          await expect(tx).to.be.revertedWith("Insufficient balance for withdrawal")
        });
    });
    describe("Granter management", async () => {
      it("Create org grant(1 confirmation org, instant)", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(1, 2, t+3, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        expect((await grants.activeGrants(1)).unlockTime.toNumber()).to.be.equal(t+3);
      });
      it("Create raw grant(1 confirmation org, instant)", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(1, 0, t+3, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, signers[0].address);
        expect((await grants.activeGrants(2)).rawGrantee).to.be.equal(signers[0].address);
      });
      it("Create grant(1 confirmation org, instant) w/ insufficient balance", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        let tx = grants.proposeGrant(1, 2, t+1, {tokens:[token.address], amounts:[ethers.utils.parseEther("1000")]}, "0x0000000000000000000000000000000000000000");
        expect(tx).to.be.reverted;
      });
      it("Propose org grant", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(2, 1, t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        expect((await grants.proposedGrants(2,1)).proposedGrant.unlockTime.toNumber()).to.be.equal(t+1000);
      });
      it("Confirm org grant", async () => {
        await granters[1].confirmGrant(2, 1);
        expect((await grants.proposedGrants(2,1)).confirmations[0]).to.be.equal(2);
      });
      it("Create org grant(3 confirmation org)", async () => {
        await granters[2].confirmGrant(2, 1);
        expect((await grants.activeGrants(3,)).grantee).to.be.equal(1);
      });

    it("Propose raw grant", async () => {
      let t = (await provider.getBlock("latest")).timestamp;
      await grants.proposeGrant(2, 0, t+3, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, signers[0].address);
      expect((await grants.proposedGrants(2,2)).proposedGrant.rawGrantee).to.be.equal(signers[0].address);
    });
    it("Confirm raw grant", async () => {
      await granters[1].confirmGrant(2, 2);
      expect((await grants.proposedGrants(2,2)).confirmations[0]).to.be.equal(2);
    });
    it("Create raw grant(3 confirmation org)", async () => {
      await granters[2].confirmGrant(2, 2);
      expect((await grants.activeGrants(4,)).rawGrantee).to.be.equal(signers[0].address);
    });
    it("revoke single grant(1 conf, instant)", async () => {
      let t = (await provider.getBlock("latest")).timestamp;
      await grants.proposeGrant(1, 2,t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
      await grants.proposeGrantRevoke(1, 5);
        expect((await grants.activeGrants(5,)).unlockTime).to.be.equal(BigNumber.from("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
    });
      it("revoke all grant(1 conf, instant)", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(1, 2,t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        await grants.proposeGrant(1, 2,t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        await grants.proposeRevokeAll(1, );
        expect((await grants.activeGrants(6,)).unlockTime).to.be.equal(BigNumber.from("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
        expect((await grants.activeGrants(7,)).unlockTime).to.be.equal(BigNumber.from("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
      });
      it("propose revoke all grant", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(2, 1,t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        await grants.proposeGrant(2, 1,t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        expect(await grants.proposeRevokeAll(2, ));
      });
      it("Confirm revoke all grant", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await granters[1].confirmGrantRevoke(2,1);
        expect((await grants.proposedGrantRevokes(2,1)).confirmations[0]).to.be.equal(2);
      });
      it("Revoke all grant(3 confs)", async () => {

        await granters[2].confirmGrantRevoke(2,1);
        expect((await grants.activeGrants(6,)).unlockTime).to.be.equal(BigNumber.from("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
        expect((await grants.activeGrants(7,)).unlockTime).to.be.equal(BigNumber.from("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
      });
    });
    describe("Claim management", async () => {
      it("Claim 1 org grant", async () => {
        await granters[2].claimGrant(1);
        expect((await grants.balances(2, token.address))).to.be.equal(ethers.utils.parseEther("99"));
      });
      it("Claim 1 raw grant", async () => {
          await granters[2].claimGrant(2);
          expect(await token.balanceOf(signers[0].address)).to.be.equal(ethers.utils.parseEther("804"));
      });
      it("Claim grant too early", async () => {
        let tx = granters[2].claimGrant(3);
        expect(tx).to.be.revertedWith("grant is still locked");
      });
      it("Claim all org", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(1, 2, t, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        await grants.proposeGrant(1, 2, t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");
        await grants.proposeGrant(1, 2, t, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, "0x0000000000000000000000000000000000000000");

        await granters[2].claimAll(2,"0x0000000000000000000000000000000000000000");
        expect((await grants.balances(2, token.address))).to.be.equal(ethers.utils.parseEther("101"));
      });
      it("Claim all raw", async () => {
        let t = (await provider.getBlock("latest")).timestamp;
        await grants.proposeGrant(1, 0, t, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, signers[0].address);
        await grants.proposeGrant(1, 0, t+1000, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, signers[0].address);
        await grants.proposeGrant(1, 0, t, {tokens:[token.address], amounts:[ethers.utils.parseEther("1")]}, signers[0].address);
        await granters[2].claimAll(0, signers[0].address);
        expect(await token.balanceOf(signers[0].address)).to.be.equal(ethers.utils.parseEther("806"));
      });
    });

  })
});
