import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre, { ethers } from "hardhat";
  import { Address } from "../typechain-types";
  
  describe("Close position Tests", function () {
    async function deployPriceFeed() {
      const [owner, otherAccount] = await hre.ethers.getSigners();
  
      const Oracle = await hre.ethers.getContractFactory("Oracle");
      const oracle = await Oracle.deploy();
  
      const StableCoin = await hre.ethers.getContractFactory("USDT");
      const stablecoin = await StableCoin.deploy();
  
      const VariableToken = await hre.ethers.getContractFactory("VariableToken");
      const variableToken = await VariableToken.deploy();
  
      await stablecoin.mint(otherAccount.address, ethers.parseEther("5000"));
  
      const price = ethers.parseUnits("2400", 18);
  
      await oracle.connect(owner).setPrice(price, variableToken.target);
  
      const MarketRegistry = await hre.ethers.getContractFactory(
        "MarketRegistry"
      );
      const marketRegistry = await MarketRegistry.deploy();
  
      const PositionManagerModel = await hre.ethers.getContractFactory(
        "PositionManager"
      );
      const positionManagerModel = await PositionManagerModel.deploy();
  
      const Vault = await hre.ethers.getContractFactory("Vault");
      const vault = await Vault.deploy();
      await vault.connect(owner).setCollateralTokenAddress(stablecoin.target);
  
      await marketRegistry.setCollateralTokenAddress(stablecoin.target);
      await marketRegistry.setOracleAddress(oracle.target);
      await marketRegistry.setVaultAddress(vault.target);
      await marketRegistry.setFactoryPositionManager(positionManagerModel);
  
      const marketParams = {
        priceFeedAddress: variableToken.target,
        assetSize: 80000,
        decimals: 18,
        maximumLeverage: 1500,
      };
      const newPositionManagerAddress =
        await marketRegistry.createNewMarket.staticCall(marketParams);
      // console.log({ newPositionManagerAddress });
      const tx = await marketRegistry.createNewMarket(marketParams);
      await tx.wait(1);
      const expectedObj = await marketRegistry.markets(
        marketParams.priceFeedAddress
      );
      // console.log({ expectedObj });
  
      const positionManager = await hre.ethers.getContractAt(
        "PositionManager",
        newPositionManagerAddress
      );
  
      await stablecoin
        .connect(owner)
        .approve(positionManager.target, ethers.parseEther("2000"));
  
        await stablecoin
        .connect(owner)
        .mint(otherAccount, ethers.parseEther("2000"));

        await stablecoin
        .connect(owner)
        .mint(vault.target, ethers.parseEther("2000000"));
  
      const userParams = {
        leverage: 500,
        collateralAmount: ethers.parseEther("1000"),
        positionOwner: owner.address,
        priceFeedAddress: variableToken.target,
        longOrShort: 0,
      };
  
      await positionManager.connect(owner).createMarketPosition(userParams);
      const topId = await positionManager.getTopLongsByBytes32();
      console.log({ topId });
      const newObject = await positionManager.idToPositionMappings(topId[0]);
      console.log({ newObject });
  
      return {
        owner,
        otherAccount,
        oracle,
        stablecoin,
        variableToken,
        marketRegistry,
        vault,
        positionManager,
        price,
        newObject,
      };
    }
  
    describe("Close open positions", function () {
      it("should close a long when the price of the asset has not changed", async function () {
          const {
              owner,
              stablecoin,
              positionManager,
              newObject,
          } = await loadFixture(deployPriceFeed);
          let topId = await positionManager.getTopLongsByBytes32();
          console.log({topId})

          await positionManager.connect(owner).closePosition(topId[0]);
          
      });
      
      it.only("should close a long when the user of the asset is in profit", async function () {
          const {
              owner,
              stablecoin,
              positionManager,
              newObject,
              oracle,
              variableToken
          } = await loadFixture(deployPriceFeed);

          let topId = await positionManager.getTopLongsByBytes32();
          console.log({topId})
          await oracle.connect(owner).setPrice(ethers.parseUnits("2900", 18), variableToken.target); // price higher than liquidation price
          await positionManager.connect(owner).closePosition(topId[0]);
      
      });
      it("should close a long when the user of the asset is in loss", async function () {
        const {
            owner,
            stablecoin,
            positionManager,
            newObject,
            oracle,
            variableToken
        } = await loadFixture(deployPriceFeed);

        let topId = await positionManager.getTopLongsByBytes32();
        console.log({topId})
        await oracle.connect(owner).setPrice(ethers.parseUnits("2000", 18), variableToken.target); // price higher than liquidation price
        await positionManager.connect(owner).closePosition(topId[0]);
    
    });
      it("should close a short when the price of the position has not changed", async function() {
          const {
              owner,
              positionManager,
              newObject,
          } = await loadFixture(deployPriceFeed);
  
          
      });
      it("should close a short when the price of the position has changed", async function() {
          
      });
     
   
    });
  });
  