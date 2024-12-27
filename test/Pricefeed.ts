import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre, { ethers } from "hardhat";


  describe("Pricefeed Tests", function(){
    async function deployPriceFeed() {
        const [owner, otherAccount] = await hre.ethers.getSigners();

        const Pricefeed = await hre.ethers.getContractFactory("Oracle");
        const pricefeed = await Pricefeed.deploy();


        const StableCoin = await hre.ethers.getContractFactory("USDT");
        const stablecoin = await StableCoin.deploy();

        return {owner, otherAccount, pricefeed, stablecoin};
    }

    describe("Basic Test", function(){
        it("should set a token price", async function(){
            const {pricefeed, owner,stablecoin} = await loadFixture(deployPriceFeed);
            const price = 5000;
            // const otherPrice = ethers.parseUnits("2512", 18);
            await pricefeed.connect(owner).setPrice(price, stablecoin.target);
            const priceFromContract = await pricefeed.getAssetPrice(stablecoin.target);
            console.log({priceFromContract})
            expect(priceFromContract).to.equal(5000)
        })
    })
  })