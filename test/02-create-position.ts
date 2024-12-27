import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Address } from "../typechain-types";

describe("Create Position Tests", function () {
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
      maximumLeverage: 15,
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

    return {
      owner,
      otherAccount,
      oracle,
      stablecoin,
      variableToken,
      marketRegistry,
      vault,
      positionManager,
      price
    };
  }

  describe("Market Creation", function () {
    it("should view the state of the position manager", async function () {
      const {
        oracle,
        owner,
        stablecoin,
        otherAccount,
        variableToken,
        marketRegistry,
        vault,
        positionManager,
      } = await loadFixture(deployPriceFeed);

      expect(await positionManager.oracleAddress()).to.equal(oracle.target);
      expect(await positionManager.pricefeedAddress()).to.equal(variableToken.target);
      expect(await positionManager.marketRegistry()).to.equal(marketRegistry.target);
      expect(await positionManager.vaultAddress()).to.equal(vault.target);
      expect(await positionManager.collateralTokenAddress()).to.equal(stablecoin.target)
      // expect(await positionManager.maintenanceMargin()).to.equal(ethers.parseEther("0.05"))
    });
    it("should create a new position", async function(){
        const {
            oracle,
            owner,
            stablecoin,
            otherAccount,
            variableToken,
            marketRegistry,
            vault,
            positionManager,
          } = await loadFixture(deployPriceFeed);

        await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("1000"));
      
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
        console.log({newObject})
    })
    it("should create two identical positions with the same price", async function(){
        const {
            oracle,
            owner,
            stablecoin,
            otherAccount,
            variableToken,
            marketRegistry,
            vault,
            positionManager,
            price
          } = await loadFixture(deployPriceFeed);

        await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("2000"));
        // await stablecoin.connect(otherAccount).approve(positionManager.target, ethers.parseEther("500"));
          
        const ownerParams = {
            leverage: 500,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        }


        await positionManager.connect(owner).createMarketPosition(ownerParams);
        await positionManager.connect(owner).createMarketPosition(ownerParams);
        
     

        const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address)
        console.log({ownerPositions})

        const ownerPositionObj1 = await positionManager.idToPositionMappings(ownerPositions[0]);
        const ownerPositionObj2 = await positionManager.idToPositionMappings(ownerPositions[1]);

        console.log({ownerPositionObj1, ownerPositionObj2})

        const positionsAt2040 = await positionManager.getLiquidationMappingsFromPrice(ownerPositionObj1[1]);
        console.log({positionsAt2040})
        expect(ownerPositionObj1).not.to.equal(ownerPositionObj2)
        expect(positionsAt2040.length).to.equal(2)
        expect(positionsAt2040[0]).not.to.equal(positionsAt2040[1]) //confirm that nonce changes the positionIds

    })
    it("should create two positions with different liquidation prices", async function(){
        const {
            oracle,
            owner,
            stablecoin,
            otherAccount,
            variableToken,
            marketRegistry,
            vault,
            positionManager,
            price
        } = await loadFixture(deployPriceFeed);
    
        // Approve enough collateral for both positions
        await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("2000"));
    
        // First position - higher leverage = higher liquidation price
        const firstPositionParams = {
            leverage: 1000,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        };
    
        // Second position - lower leverage = lower liquidation price
        const secondPositionParams = {
            leverage: 500,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        };
    
        // Create both positions
        await positionManager.connect(owner).createMarketPosition(firstPositionParams);
        await positionManager.connect(owner).createMarketPosition(secondPositionParams);
    
        // Get all positions for owner
        const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address);
        console.log("Owner positions:", ownerPositions);
    
        // Get position objects
        const firstPosition = await positionManager.idToPositionMappings(ownerPositions[0]);
        const secondPosition = await positionManager.idToPositionMappings(ownerPositions[1]);
        console.log("First position liquidation price:", firstPosition.liquidationPrice.toString());
        console.log("Second position liquidation price:", secondPosition.liquidationPrice.toString());
    
        // Get top longs - should match the position with higher liquidation price
        const topLongs = await positionManager.getTopLongsByBytes32();
        console.log("Top longs:", topLongs);
    
        // Verify positions at each liquidation price
        const positionsAtFirstPrice = await positionManager.getLiquidationMappingsFromPrice(firstPosition.liquidationPrice);
        const positionsAtSecondPrice = await positionManager.getLiquidationMappingsFromPrice(secondPosition.liquidationPrice);
        console.log("Positions at first price:", positionsAtFirstPrice);
        console.log("Positions at second price:", positionsAtSecondPrice);
    
        // Assertions
        expect(firstPosition.liquidationPrice).to.not.equal(secondPosition.liquidationPrice, "Liquidation prices should be different");
        expect(positionsAtFirstPrice.length).to.equal(1, "Should have one position at first price");
        expect(positionsAtSecondPrice.length).to.equal(1, "Should have one position at second price");
        expect(topLongs[0]).to.equal(ownerPositions[0], "Top long should be the first position (higher leverage)");
    
        // Check if positions are properly ordered in the skip list
        const topLongsByObject = await positionManager.getTopLongsByObject();
        expect(topLongsByObject[0].leverage).to.equal(1000, "Highest leverage position should be first");
    });
    it("should create positions from two different users with different parameters", async function(){
        const {
            oracle,
            owner,
            stablecoin,
            otherAccount,
            variableToken,
            marketRegistry,
            vault,
            positionManager,
            price
        } = await loadFixture(deployPriceFeed);
    
        // Approve collateral for both users
        await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("1000"));
        await stablecoin.connect(otherAccount).approve(positionManager.target, ethers.parseEther("500"));
        
        // First user (owner) - higher leverage and collateral
        const ownerParams = {
            leverage: 500,
            collateralAmount: ethers.parseEther("1000"),
            positionOwner: owner.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        };
    
        // Second user (otherAccount) - lower leverage and collateral
        const otherAccountParams = {
            leverage: 200,
            collateralAmount: ethers.parseEther("500"),
            positionOwner: otherAccount.address,
            priceFeedAddress: variableToken.target,
            longOrShort: 0
        };
    
        // Create positions
        await positionManager.connect(owner).createMarketPosition(ownerParams);
        await positionManager.connect(otherAccount).createMarketPosition(otherAccountParams);
    
        // Get positions for both users
        const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address);
        const otherAccountPositions = await positionManager.getAllPositionsFromUser(otherAccount.address);
        console.log({ownerPositions, otherAccountPositions});
    
        // Get position objects
        const ownerPositionObj = await positionManager.idToPositionMappings(ownerPositions[0]);
        const otherAccountPositionObj = await positionManager.idToPositionMappings(otherAccountPositions[0]);
        console.log({ownerPositionObj, otherAccountPositionObj});
    
        // Get positions at the entry price
        const positionsAt2400 = await positionManager.getLiquidationMappingsFromPrice(ownerPositionObj.liquidationPrice);
        console.log({positionsAt2400});
    
        // Assertions
        // Verify positions exist and are different
        expect(ownerPositions.length).to.equal(1, "Owner should have 1 position");
        expect(otherAccountPositions.length).to.equal(1, "Other account should have 1 position");
        expect(ownerPositions[0]).to.not.equal(otherAccountPositions[0], "Position IDs should be different");
    
        // Verify position details
        expect(ownerPositionObj.positionOwner).to.equal(owner.address);
        expect(ownerPositionObj.leverage).to.equal(500);
        expect(ownerPositionObj.collateral).to.equal(ethers.parseEther("1000"));
    
        expect(otherAccountPositionObj.positionOwner).to.equal(otherAccount.address);
        expect(otherAccountPositionObj.leverage).to.equal(200);
        expect(otherAccountPositionObj.collateral).to.equal(ethers.parseEther("500"));
    
        // Verify liquidation prices are different (due to different leverages)
        expect(ownerPositionObj.liquidationPrice).to.not.equal(otherAccountPositionObj.liquidationPrice, 
            "Liquidation prices should be different due to different leverages");
    
        // Verify position ordering in skip list (higher leverage should be first)
        const topLongs = await positionManager.getTopLongsByBytes32();
        expect(topLongs[0]).to.equal(ownerPositions[0], 
            "Owner's position should be first in top longs due to higher leverage");
    });
    describe("Short Position Creation", function () {
        it("should create a new short position", async function(){
            const {
                oracle,
                owner,
                stablecoin,
                otherAccount,
                variableToken,
                marketRegistry,
                vault,
                positionManager,
            } = await loadFixture(deployPriceFeed);
    
            await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("1000"));
          
            const userParams = {
                leverage: 200,
                collateralAmount: ethers.parseEther("1000"),
                positionOwner: owner.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            }
            
            await positionManager.connect(owner).createMarketPosition(userParams);
            const topId = await positionManager.getTopShortsByBytes32();
            console.log({topId})
            const newObject = await positionManager.idToPositionMappings(topId[0]);
            console.log({newObject})
        });
    
        it("should create two identical short positions with the same price", async function(){
            const {
                oracle,
                owner,
                stablecoin,
                otherAccount,
                variableToken,
                marketRegistry,
                vault,
                positionManager,
                price
            } = await loadFixture(deployPriceFeed);
    
            await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("2000"));
              
            const ownerParams = {
                leverage: 500,
                collateralAmount: ethers.parseEther("1000"),
                positionOwner: owner.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            }
    
            await positionManager.connect(owner).createMarketPosition(ownerParams);
            await positionManager.connect(owner).createMarketPosition(ownerParams);
            
            const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address)
            console.log({ownerPositions})
    
            const ownerPositionObj1 = await positionManager.idToPositionMappings(ownerPositions[0]);
            const ownerPositionObj2 = await positionManager.idToPositionMappings(ownerPositions[1]);
    
            console.log({ownerPositionObj1, ownerPositionObj2})
    
            const positionsAt2040 = await positionManager.getLiquidationMappingsFromPrice(ownerPositionObj1[1]);
            console.log({positionsAt2040})
            expect(ownerPositionObj1).not.to.equal(ownerPositionObj2)
            expect(positionsAt2040.length).to.equal(2)
            expect(positionsAt2040[0]).not.to.equal(positionsAt2040[1])
        });
    
        it("should create two short positions with different prices", async function(){
            const {
                oracle,
                owner,
                stablecoin,
                otherAccount,
                variableToken,
                marketRegistry,
                vault,
                positionManager,
                price
            } = await loadFixture(deployPriceFeed);
        
            await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("2000"));
        
            // First position - higher leverage = lower liquidation price for shorts
            const firstPositionParams = {
                leverage: 1000,
                collateralAmount: ethers.parseEther("1000"),
                positionOwner: owner.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            };
        
            // Second position - lower leverage = higher liquidation price for shorts
            const secondPositionParams = {
                leverage: 500,
                collateralAmount: ethers.parseEther("1000"),
                positionOwner: owner.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            };
        
            await positionManager.connect(owner).createMarketPosition(firstPositionParams);
            await positionManager.connect(owner).createMarketPosition(secondPositionParams);
        
            const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address);
            console.log("Owner positions:", ownerPositions);
        
            const firstPosition = await positionManager.idToPositionMappings(ownerPositions[0]);
            const secondPosition = await positionManager.idToPositionMappings(ownerPositions[1]);
            console.log("First position liquidation price:", firstPosition.liquidationPrice.toString());
            console.log("Second position liquidation price:", secondPosition.liquidationPrice.toString());
        
            // Get top shorts - should match the position with lower liquidation price
            const topShorts = await positionManager.getTopShortsByBytes32();
            console.log("Top shorts:", topShorts);
        
            const positionsAtFirstPrice = await positionManager.getLiquidationMappingsFromPrice(firstPosition.liquidationPrice);
            const positionsAtSecondPrice = await positionManager.getLiquidationMappingsFromPrice(secondPosition.liquidationPrice);
            console.log("Positions at first price:", positionsAtFirstPrice);
            console.log("Positions at second price:", positionsAtSecondPrice);
        
            expect(firstPosition.liquidationPrice).to.not.equal(secondPosition.liquidationPrice, "Liquidation prices should be different");
            expect(positionsAtFirstPrice.length).to.equal(1, "Should have one position at first price");
            expect(positionsAtSecondPrice.length).to.equal(1, "Should have one position at second price");
            expect(topShorts[0]).to.equal(ownerPositions[0], "Top short should be the first position (higher leverage = lower liquidation price)");
        });
    
        it("should create short positions from two different users with different parameters", async function(){
            const {
                oracle,
                owner,
                stablecoin,
                otherAccount,
                variableToken,
                marketRegistry,
                vault,
                positionManager,
                price
            } = await loadFixture(deployPriceFeed);
        
            await stablecoin.connect(owner).approve(positionManager.target, ethers.parseEther("1000"));
            await stablecoin.connect(otherAccount).approve(positionManager.target, ethers.parseEther("500"));
            
            const ownerParams = {
                leverage: 500,
                collateralAmount: ethers.parseEther("1000"),
                positionOwner: owner.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            };
        
            const otherAccountParams = {
                leverage: 200,
                collateralAmount: ethers.parseEther("500"),
                positionOwner: otherAccount.address,
                priceFeedAddress: variableToken.target,
                longOrShort: 1  // Short position
            };
        
            await positionManager.connect(owner).createMarketPosition(ownerParams);
            await positionManager.connect(otherAccount).createMarketPosition(otherAccountParams);
        
            const ownerPositions = await positionManager.getAllPositionsFromUser(owner.address);
            const otherAccountPositions = await positionManager.getAllPositionsFromUser(otherAccount.address);
            console.log({ownerPositions, otherAccountPositions});
        
            const ownerPositionObj = await positionManager.idToPositionMappings(ownerPositions[0]);
            const otherAccountPositionObj = await positionManager.idToPositionMappings(otherAccountPositions[0]);
            console.log({ownerPositionObj, otherAccountPositionObj});
        
            const positionsAtPrice = await positionManager.getLiquidationMappingsFromPrice(ownerPositionObj.liquidationPrice);
            console.log({positionsAtPrice});
        
            expect(ownerPositions.length).to.equal(1, "Owner should have 1 position");
            expect(otherAccountPositions.length).to.equal(1, "Other account should have 1 position");
            expect(ownerPositions[0]).to.not.equal(otherAccountPositions[0], "Position IDs should be different");
        
            expect(ownerPositionObj.positionOwner).to.equal(owner.address);
            expect(ownerPositionObj.leverage).to.equal(500);
            expect(ownerPositionObj.collateral).to.equal(ethers.parseEther("1000"));
        
            expect(otherAccountPositionObj.positionOwner).to.equal(otherAccount.address);
            expect(otherAccountPositionObj.leverage).to.equal(200);
            expect(otherAccountPositionObj.collateral).to.equal(ethers.parseEther("500"));
        
            expect(ownerPositionObj.liquidationPrice).to.not.equal(otherAccountPositionObj.liquidationPrice, 
                "Liquidation prices should be different due to different leverages");
        
            const topShorts = await positionManager.getTopShortsByBytes32();
            expect(topShorts[0]).to.equal(ownerPositions[0], 
                "Owner's position should be first in top shorts due to higher leverage = lower liquidation price");
        });
    });
    
  });
});
