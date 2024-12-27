import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre, { ethers } from "hardhat";
  import { Address } from "../typechain-types";
  
  describe("Liquidate Position Tests", function () {
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
  
    describe("Update Market", function () {
      it("should create a long position and liquidate the position when the price is equal to its liquidation price", async function(){
        const {oracle, owner, variableToken, positionManager, otherAccount,price} = await loadFixture(deployPriceFeed);

        //create user position
        const userParams = {
            leverage: 200,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        }

        await positionManager.connect(owner).createMarketPosition(userParams);

        const topId = await positionManager.getTopLongsByBytes32();
        console.log({topId})
        const newObject = await positionManager.idToPositionMappings(topId[0]);
        console.log({newObject});
        let checkIdIsInMapping = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("1966080000000000000000", "wei"));
        console.log({checkIdIsInMapping})

        await expect(positionManager.connect(owner).liquidatePosition(topId[0])).to.be.revertedWith("You cannot liquidate your own position");
        await expect(positionManager.connect(otherAccount).liquidatePosition(topId[0])).to.be.revertedWith("Cannot be liquidated");
        await oracle.connect(owner).setPrice(ethers.parseUnits("1966", 18), variableToken.target); // price lower than liquidation price
        let idsToBeLiquidated = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("1966080000000000000000", "wei"));
        console.log({idsToBeLiquidated})
        await positionManager.connect(otherAccount).liquidatePosition(topId[0]);

      })

      it("should create a short position and liquidate the position when the price is equal to its liquidation price", async function(){
        const {oracle, owner, variableToken, positionManager, otherAccount,price} = await loadFixture(deployPriceFeed);

        //create user position
        const userParams = {
            leverage: 200,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 1
        }

        await positionManager.connect(owner).createMarketPosition(userParams);

        const topShortsId = await positionManager.getTopShortsByBytes32();
        console.log({topShortsId})
        const newObject = await positionManager.idToPositionMappings(topShortsId[0]);
        console.log({newObject});
        // let checkIdIsInMapping = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("1966080000000000000000", "wei"));
        // console.log({checkIdIsInMapping})

        await expect(positionManager.connect(owner).liquidatePosition(topShortsId[0])).to.be.revertedWith("You cannot liquidate your own position");
        await expect(positionManager.connect(otherAccount).liquidatePosition(topShortsId[0])).to.be.revertedWith("Cannot be liquidated");
        await oracle.connect(owner).setPrice(ethers.parseUnits("3600", 18), variableToken.target); // price lower than liquidation price
        // let idsToBeLiquidated = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("1966080000000000000000", "wei"));
        // console.log({idsToBeLiquidated})
        await positionManager.connect(otherAccount).liquidatePosition(topShortsId[0]);
      })

      it("should create 2 long positions with the same liquidation price and liquidate both", async function(){
        const {oracle, owner, variableToken, positionManager, otherAccount,price} = await loadFixture(deployPriceFeed);

        const userParams = {
            leverage: 500,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0,
          };

          await positionManager.connect(owner).createMarketPosition(userParams);
          let topId = await positionManager.getTopLongsByBytes32();
        console.log({topId})
        await oracle.connect(owner).setPrice(ethers.parseUnits("1966", 18), variableToken.target); // price lower than liquidation price
        await Promise.all([positionManager.connect(otherAccount).liquidatePosition(topId[0]), positionManager.connect(otherAccount).liquidatePosition(topId[1])]); // both liquidations are succesful
        let idsToBeLiquidated = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("1966080000000000000000", "wei"));
        expect(idsToBeLiquidated.length).to.equal(0)
      })

      it("should create 2 short positions with the same liquidation price and liquidate both", async function(){
        const {oracle, owner, variableToken, positionManager, otherAccount,price} = await loadFixture(deployPriceFeed);

        const userParams = {
            leverage: 500,
            collateralAmount: ethers.parseEther("200"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 1,
          };

          await positionManager.connect(owner).createMarketPosition(userParams);
          await positionManager.connect(owner).createMarketPosition(userParams);
          let topId = await positionManager.getTopShortsByBytes32();
        console.log({topId})
        const newObject = await positionManager.idToPositionMappings(topId[0]);
        console.log({newObject});
        await oracle.connect(owner).setPrice(ethers.parseUnits("2900", 18), variableToken.target); // price higher than liquidation price
        await Promise.all([positionManager.connect(otherAccount).liquidatePosition(topId[0]), positionManager.connect(otherAccount).liquidatePosition(topId[1])]); // both liquidations are succesful
        let idsToBeLiquidated = await positionManager.connect(otherAccount).getLiquidationMappingsFromPrice(ethers.parseUnits("2833920000000000000000", "wei"));
        expect(idsToBeLiquidated.length).to.equal(0)
      })
     
   
    });
  });
  