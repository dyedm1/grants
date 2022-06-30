import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { ERC20 } from "../typechain/ERC20";
import { ERC20__factory } from "../typechain/factories/ERC20__factory";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

const { provider } = waffle;

describe("erc20", function () {
  let token: ERC20;
  const [wallet] = provider.getWallets();
  let signers: SignerWithAddress[];
  let spender: ERC20;
  before(async function () {
    signers = await ethers.getSigners();
    const deployer = new ERC20__factory(signers[0]);
    token = await deployer.deploy("token", "TKN");
    await token.mint(signers[0].address, ethers.utils.parseEther("100"));
    spender = token.connect(signers[1]);
  })
  // resets state of token - required before some tests
  async function fixture() {
    signers = await ethers.getSigners();
    const deployer = new ERC20__factory(signers[0]);
    token = await deployer.deploy("token", "TKN");
    await token.mint(signers[0].address, ethers.utils.parseEther("100"));
    spender = token.connect(signers[1]);
  }

  describe("transfer functionality", async () => {
    it("transfers successfully", async () => {
      await token.transfer(signers[1].address, ethers.utils.parseEther("5"));
      expect(await token.balanceOf(signers[0].address)).to.be.eq(
        ethers.utils.parseEther("95")
      );
      expect(await token.balanceOf(signers[1].address)).to.be.eq(
        ethers.utils.parseEther("5")
      );
    });

    it("does not transfer more than balance", async () => {
      const tx = token.transfer(
        signers[1].address,
        ethers.utils.parseEther("500")
      );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-balance");
    });
    it("does not transfer to 0x0", async () => {
      const tx = token.transfer(
        ethers.constants.AddressZero,
        ethers.utils.parseEther("5")
      );
      await expect(tx).to.be.reverted;
    });
    it("does not transfer to token address", async () => {
      const tx = token.transfer(token.address, ethers.utils.parseEther("5"));
      await expect(tx).to.be.reverted;
    });
  });

  describe("approval functionality", async () => {
    it("approves successfully", async () => {
      await token.approve(signers[1].address, ethers.utils.parseEther("5"));
      expect(
        await token.allowance(signers[0].address, signers[1].address)
      ).to.be.eq(ethers.utils.parseEther("5"));
    });
  });
  describe("transferFrom functionality", async () => {
    it("does not transferfrom without approval", async () => {
      await fixture();
      const tx = spender.transferFrom(
        signers[0].address,
        signers[1].address,
        ethers.utils.parseEther("5")
      );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-allowance");
    });

    it("does not transferfrom more than approval", async () => {
      await token.approve(signers[1].address, ethers.utils.parseEther("4"));
      const tx = spender.transferFrom(
        signers[0].address,
        signers[1].address,
        ethers.utils.parseEther("5")
      );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-allowance");
    });

    it("transferfrom transfers successfully with approval", async () => {
      await fixture();
      await token.approve(signers[1].address, ethers.utils.parseEther("5"));
      await spender.transferFrom(
        signers[0].address,
        signers[1].address,
        ethers.utils.parseEther("5")
      );
      expect(await token.balanceOf(signers[0].address)).to.be.eq(
        ethers.utils.parseEther("95")
      );
      expect(await token.balanceOf(signers[1].address)).to.be.eq(
        ethers.utils.parseEther("5")
      );
    });
    it("does not transferfrom more than balance", async () => {
      await fixture();
      await token.approve(signers[1].address, ethers.utils.parseEther("500"));
      const tx = spender.transferFrom(
          signers[0].address,
          signers[1].address,
          ethers.utils.parseEther("500")
      );
      await expect(tx).to.be.revertedWith("ERC20: insufficient-balance");
    });
    it("does not transferfrom to 0x0", async () => {
      await fixture();
      await token.approve(signers[1].address, ethers.utils.parseEther("5"));
      const tx = spender.transferFrom(
        signers[0].address,
        ethers.constants.AddressZero,
        ethers.utils.parseEther("5")
      );
      await expect(tx).to.be.reverted;
    });
    it("does not transferfrom to token address", async () => {
      await fixture();
      await token.approve(signers[1].address, ethers.utils.parseEther("5"));
      const tx = spender.transferFrom(
        signers[0].address,
        token.address,
        ethers.utils.parseEther("5")
      );
      await expect(tx).to.be.reverted;
    });
  });
});
