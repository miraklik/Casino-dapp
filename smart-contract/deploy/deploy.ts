import { ethers } from "hardhat";

async function main() {
    const [deploy] = await ethers.getSigners();

    console.log("Deploying contracts with the accounts: ", deploy.address);

    const Roulette = await ethers.getContractFactory("Roulette");
    const roulette = await Roulette.deploy();

    console.log("Contract deployed to address:", roulette.getAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });