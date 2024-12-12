import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";
import { Pricefeed } from "../typechain-types/Pricefeed";
import { Pricefeed__factory } from "../typechain-types";


  describe("Pricefeed Tests", function(){
    async function deployPriceFeed() {
        const [owner, otherAccount] = await hre.ethers.getSigners();

        const Pricefeed = await hre.ethers.getContractFactory("Pricefeed");
        const pricefeed = await Pricefeed.deploy();


        const StableCoin = await hre.ethers.getContractFactory("USDT");
        const stablecoin = await StableCoin.deploy();

        return {owner, otherAccount, pricefeed, stablecoin};
    }

    describe("Basic Test", function(){
        it.only("should set a token price", async function(){
            const {pricefeed, owner,stablecoin} = await loadFixture(deployPriceFeed);
            const price = 5000;
            await pricefeed.connect(owner).setPrice(price, stablecoin.target);
            const priceFromContract = await pricefeed.getAssetPrice(stablecoin.target);
            expect(priceFromContract).to.equal(5000)

        })
    })
  })