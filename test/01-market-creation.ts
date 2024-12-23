import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Pricefeed } from "../typechain-types/Pricefeed";
import { Pricefeed__factory } from "../typechain-types";

describe("Pricefeed Tests", function () {
  async function deployPriceFeed() {
    const [owner, otherAccount] = await hre.ethers.getSigners();

    const Pricefeed = await hre.ethers.getContractFactory("Pricefeed");
    const pricefeed = await Pricefeed.deploy();

    const StableCoin = await hre.ethers.getContractFactory("USDT");
    const stablecoin = await StableCoin.deploy();

    const VariableToken = await hre.ethers.getContractFactory("VariableToken");
    const variableToken = await VariableToken.deploy();

    const price = ethers.parseUnits("2400", 18);

    await pricefeed.connect(owner).setPrice(price, variableToken.target);


    const MarketRegistry = await hre.ethers.getContractFactory(
      "MarketRegistry"
    );
    const marketRegistry = await MarketRegistry.deploy();

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = await Vault.deploy();
    await vault.connect(owner).setCollateralTokenAddress(stablecoin.target);

    return {
      owner,
      otherAccount,
      pricefeed,
      stablecoin,
      variableToken,
    //   priceFromContract,
      marketRegistry,
      vault,
    };
  }

  describe("Market Creation", function () {
    it.only("should create a new market", async function () {
      const { pricefeed, owner, stablecoin, otherAccount, variableToken, marketRegistry, vault } = await loadFixture(
        deployPriceFeed
      );
      const marketParams = {
        
      }
    //   const newPositionManager = await marketRegistry.createNewMarket.staticCall();
    });
  });
});
