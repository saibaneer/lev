import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Address } from "../typechain-types";

describe("Update Position Tests", function () {
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
    it("should update an existing position with a positive amount and reduce leverage", async function () {
        const {
            owner,
            stablecoin,
            positionManager,
            newObject,
        } = await loadFixture(deployPriceFeed);
    
        // Approve additional collateral
        const additionalAmount = ethers.parseEther("1000"); // Double collateral
        await stablecoin.connect(owner).approve(positionManager.target, additionalAmount);
    
        // Store initial values
        const initialCollateral = newObject.collateral;
        const initialLeverage = newObject.leverage;
        const initialPositionSize = newObject.positionSize;
        const initialLiquidationPrice = newObject.liquidationPrice;
    
        console.log("Initial Position:", {
            collateral: ethers.formatEther(initialCollateral),
            leverage: initialLeverage.toString(),
            positionSize: ethers.formatEther(initialPositionSize),
            liquidationPrice: ethers.formatEther(initialLiquidationPrice)
        });
    
        await positionManager.connect(owner).updatePosition(newObject[6], additionalAmount);
        
        const updatedPosition = await positionManager.idToPositionMappings(newObject[6]);
        console.log("Updated Position:", {
            collateral: ethers.formatEther(updatedPosition.collateral),
            leverage: updatedPosition.leverage.toString(),
            positionSize: ethers.formatEther(updatedPosition.positionSize),
            liquidationPrice: ethers.formatEther(updatedPosition.liquidationPrice)
        });
    
        // Verify changes
        expect(updatedPosition.collateral).to.equal(initialCollateral + additionalAmount);
        expect(updatedPosition.positionSize).to.equal(initialPositionSize); // Position size should stay same
        expect(updatedPosition.leverage).to.equal(250); // 5x -> 2.5x (500 -> 250)
        expect(updatedPosition.liquidationPrice).to.be.lt(initialLiquidationPrice);
    
        // Verify skip list updates
        const newLiquidationMappings = await positionManager.getLiquidationMappingsFromPrice(updatedPosition.liquidationPrice);
        expect(newLiquidationMappings).to.include(newObject[6]);
    });
    
    it("should update an existing position with a negative amount and increase leverage", async function () {
        const {
            owner,
            stablecoin,
            positionManager,
            newObject,
        } = await loadFixture(deployPriceFeed);
    
        // Store initial values
        const initialCollateral = newObject.collateral;
        const initialLeverage = newObject.leverage;
        const initialPositionSize = newObject.positionSize;
        const initialLiquidationPrice = newObject.liquidationPrice;
    
        console.log("Initial Position:", {
            collateral: ethers.formatEther(initialCollateral),
            leverage: initialLeverage.toString(),
            positionSize: ethers.formatEther(initialPositionSize),
            liquidationPrice: ethers.formatEther(initialLiquidationPrice)
        });
    
        // Reduce collateral by half
        const reductionAmount = ethers.parseEther("500");
        await positionManager.connect(owner).updatePosition(newObject[6], -reductionAmount);
        
        const updatedPosition = await positionManager.idToPositionMappings(newObject[6]);
        console.log("Updated Position:", {
            collateral: ethers.formatEther(updatedPosition.collateral),
            leverage: updatedPosition.leverage.toString(),
            positionSize: ethers.formatEther(updatedPosition.positionSize),
            liquidationPrice: ethers.formatEther(updatedPosition.liquidationPrice)
        });
    
        // Verify changes
        expect(updatedPosition.collateral).to.equal(initialCollateral - reductionAmount);
        expect(updatedPosition.positionSize).to.equal(initialPositionSize); // Position size should stay same
        expect(updatedPosition.leverage).to.equal(1000); // 5x -> 10x (500 -> 1000)
        expect(updatedPosition.liquidationPrice).to.be.gt(initialLiquidationPrice);
    
        // Verify skip list updates
        const newLiquidationMappings = await positionManager.getLiquidationMappingsFromPrice(updatedPosition.liquidationPrice);
        expect(newLiquidationMappings).to.include(newObject[6]);
    });
    it("should fail when trying to remove more collateral than available", async function() {
        const {
            owner,
            positionManager,
            newObject,
        } = await loadFixture(deployPriceFeed);

        const tooLargeReduction = ethers.parseUnits("-1100", 18); // More than initial 1000

        await expect(
            positionManager.connect(owner).updatePosition(newObject[6], tooLargeReduction)
        ).to.be.revertedWith("Invalid collateral amount");
    });
    it("should fail when trying to update non-existent position", async function() {
        const {
            owner,
            positionManager,
        } = await loadFixture(deployPriceFeed);

        const fakePositionId = ethers.randomBytes(32);
        const amount = ethers.parseUnits("100", 18);

        await expect(
            positionManager.connect(owner).updatePosition(fakePositionId, amount)
        ).to.be.revertedWith("Position does not exist");
    });
    it("should fail when non-owner tries to update position", async function() {
        const {
            otherAccount,
            positionManager,
            newObject,
        } = await loadFixture(deployPriceFeed);

        const amount = ethers.parseUnits("100", 18);

        await expect(
            positionManager.connect(otherAccount).updatePosition(newObject[6], amount)
        ).to.be.revertedWith("Sender != Owner");
    });
   
 
  });
});
