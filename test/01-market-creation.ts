import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Address } from "../typechain-types";

describe("Market Creation Tests", function () {
  async function deployPriceFeed() {
    const [owner, otherAccount] = await hre.ethers.getSigners();

    const Oracle = await hre.ethers.getContractFactory("Oracle");
    const oracle = await Oracle.deploy();

    const StableCoin = await hre.ethers.getContractFactory("USDT");
    const stablecoin = await StableCoin.deploy();

    const VariableToken = await hre.ethers.getContractFactory("VariableToken");
    const variableToken = await VariableToken.deploy();

    const price = ethers.parseUnits("2400", 18);

    await oracle.connect(owner).setPrice(price, variableToken.target);


    const MarketRegistry = await hre.ethers.getContractFactory(
      "MarketRegistry"
    );
    const marketRegistry = await MarketRegistry.deploy();

    const PositionManagerModel = await hre.ethers.getContractFactory("PositionManager");
    const positionManagerModel = await PositionManagerModel.deploy();

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = await Vault.deploy();
    await vault.connect(owner).setCollateralTokenAddress(stablecoin.target);

    await marketRegistry.setCollateralTokenAddress(stablecoin.target);
    await marketRegistry.setOracleAddress(oracle.target);
    await marketRegistry.setVaultAddress(vault.target);
    await marketRegistry.setFactoryPositionManager(positionManagerModel);

    return {
      owner,
      otherAccount,
      oracle,
      stablecoin,
      variableToken,
    //   priceFromContract,
      marketRegistry,
      vault,
    };
  }

  describe("Market Creation", function () {
    it("should create a new market", async function () {
      const { oracle, owner, stablecoin, otherAccount, variableToken, marketRegistry, vault } = await loadFixture(
        deployPriceFeed
      );

    //   struct MarketCreationParams {
    //     address priceFeedAddress; // unique identifier
    //     uint256 assetSize;
    //     uint256 decimals;
    //     uint256 maximumLeverage;
    // }
      const marketParams = {
        priceFeedAddress: variableToken.target,
        assetSize: 80000,
        decimals: 18,
        maximumLeverage: 15
      }
      let newPositionManager = await marketRegistry.createNewMarket.staticCall(marketParams);
      console.log({newPositionManager})
      const tx = await marketRegistry.createNewMarket(marketParams);
      await tx.wait(1)
      const expectedObj = await marketRegistry.markets(marketParams.priceFeedAddress);
      console.log({expectedObj})
    });
  });
});
