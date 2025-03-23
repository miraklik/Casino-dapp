import { ethers } from "hardhat";
import { expect } from "chai";
import { Roulette, VipNFT, VRFCoordinatorV2Mock } from "../typechain-types";

describe("Roulette Contract", () => {
  let roulette: Roulette;
  let vipNFT: VipNFT;
  let vrfCoordinatorMock: VRFCoordinatorV2Mock;
  let owner: any, user: any;
  const subscriptionId = 1;
  const keyHash = ethers.decodeBytes32String("keyhash");

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    const VRFCoordinatorMock = await ethers.getContractFactory("VRFCoordinatorV2Mock");
    vrfCoordinatorMock = await VRFCoordinatorMock.deploy(0, 0);
    await vrfCoordinatorMock.createSubscription();
    await vrfCoordinatorMock.fundSubscription(subscriptionId, ethers.parseEther("10"));

    const VipNFT = await ethers.getContractFactory("VipNFT");
    vipNFT = await VipNFT.deploy(owner.address);

    const RouletteFactory = await ethers.getContractFactory("Roulette");
    roulette = await RouletteFactory.deploy(subscriptionId, vipNFT.address);

    await owner.sendTransaction({
      to: roulette.address,
      value: ethers.parseEther("10"),
    });
  });

  describe("Place Multi Bet", () => {
    it("Should successfully place a bet", async () => {
      const betAmount = ethers.parseEther("0.01");
      const tx = await roulette.connect(user).placeMultiBet(
        true, 5, // betOnNumber=true, number=5
        false, false, // betOnColor=false
        false, // betOnGreen=false
        true, false, // betOnEven=true, betOnOdd=false
        { value: betAmount }
      );

      const receipt = await tx.wait();
      const requestId = receipt.events?.find((e: any) => e.event === "BetPlaced")?.args?.requestId;

      expect(requestId).to.exist;
      expect(await roulette.houseBank()).to.be.gt(0);
    });

    it("Should fail if bet is below minimum", async () => {
      const smallBet = ethers.parseEther("0.0001");
      await expect(
        roulette.connect(user).placeMultiBet(
          false, 0, false, false, false, false, false,
          { value: smallBet }
        )
      ).to.be.revertedWithCustomError(roulette, "BetIsBelowMinimum");
    });
  });

  describe("Chainlink VRF Callback", () => {
    it("Should handle VRF callback and payout correctly", async () => {
      const betAmount = ethers.parseEther("0.01");
      const tx = await roulette.connect(user).placeMultiBet(
        true, 17, false, false, false, false, false,
        { value: betAmount }
      );

      const receipt = await tx.wait();
      const requestId = receipt.events?.find((e: any) => e.event === "BetPlaced")?.args?.requestId;

      await vrfCoordinatorMock.fulfillRandomWords(requestId, roulette.address);

      const bet = await roulette.bets(requestId);
      expect(bet.player).to.equal(ethers.ZeroAddress); 
    });
  });

  describe("VIP Benefits", () => {
    it("Should return correct VIP benefits", async () => {
      await vipNFT.setVipLevel(user.address, 2);

      const [adjustedMaxBet, adjustedHouseFee, cashback, winBonus] =
        await roulette.getVipBenefits(user.address);

      expect(adjustedMaxBet).to.equal(ethers.parseEther("10"));
      expect(adjustedHouseFee).to.equal(2);
      expect(cashback).to.equal(5);
      expect(winBonus).to.equal(10);
    });
  });

});
