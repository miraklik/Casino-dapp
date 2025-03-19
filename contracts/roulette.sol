// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./VipNFT.sol";

/**
 * @title Roulette Smart Contract
 * @notice A decentralized roulette game with VIP NFT integration and Chainlink VRF random number generation.
 * @dev This contract allows users to place bets, receive winnings, and benefit from VIP NFT perks.
 */
contract Roulette is VRFConsumerBaseV2, Ownable {
    VRFCoordinatorV2Interface private immutable COORDINATOR;
    VipNFT public immutable vipNft;

    // Custom error messages for gas optimization
    error InvalidNum();
    error InvalidBetLimits();
    error BetIsBelowMinimum();
    error BetExceedsMaximum();
    error CannotBetOnBothEVENAndODD();
    error CannotBetOnColorAndGreenSimultaneously();
    error NotEnoughFundsInHouseBank();
    error CashBackTransferFailed();
    error TransferFailed();
    error WithdrawFailed();

    // Chainlink VRF parameters
    uint64 private immutable subscriptionId;
    address private immutable vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; 
    bytes32 private immutable keyHash; //Insert your KEY_HASH 
    uint32 private constant callbackGasLimit = 200000;
    uint16 private constant requestConfirmations = 3;
    uint32 private constant numWords = 1;

    // Betting parameters
    uint256 public minBet = 0.001 ether;
    uint256 public maxBet = 5 ether;
    uint256 public houseBank;
    uint256 public houseFee = 5; 

    /**
     * @dev Represents a bet placed by a user.
     */
    struct MultiBet {
        address player;
        uint256 amount;
        bool betOnNumber;
        uint8 number;
        bool betOnColor;
        bool color; 
        bool betOnGreen;
        bool betOnEven;
        bool betOnOdd;
    }

    // Mapping requestId to bets
    mapping(uint256 => MultiBet) public bets;

    // Events
    event BetPlaced(uint256 requestId, address indexed player, uint256 amount);
    event GameResult(uint256 requestId, address indexed player, uint256 amount, uint8 winningNumber, bool win);
    event HouseBankUpdated(uint256 newBalance);

    /**
     * @notice Initializes the Roulette contract with Chainlink VRF and VIP NFT contract.
     * @param _subscriptionId Chainlink VRF subscription ID.
     * @param _vipNFT Address of the VIP NFT contract.
     */
    constructor(uint64 _subscriptionId, address _vipNFT) VRFConsumerBaseV2(vrfCoordinator) Ownable(msg.sender) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        subscriptionId = _subscriptionId;
        vipNft = VipNFT(_vipNFT);
    }

    /**
     * @notice Retrieves VIP benefits for a given player.
     * @param player The address of the player.
     * @return adjustedMaxBet Maximum bet limit based on VIP status.
     * @return adjustedHouseFee House fee percentage based on VIP status.
     * @return cashback Cashback percentage for the player.
     * @return winBonus Win multiplier bonus.
     */
    function getVipBenefits(address player) public view returns (uint256, uint256, uint256, uint256) {
        uint256 level = uint256(vipNft.getVipLevel(player));

        uint256 adjustedMaxBet = maxBet;
        uint256 adjustedHouseFee = houseFee;
        uint256 cashback = 0;
        uint256 winBonus = 0;

        if (level == uint256(VipNFT.VipLevel.SILVER)) {
            adjustedMaxBet += 2 ether;
            adjustedHouseFee = 3;
            cashback = 2;
            winBonus = 5;
        } else if (level == uint256(VipNFT.VipLevel.GOLD)) {
            adjustedMaxBet += 5 ether;
            adjustedHouseFee = 2;
            cashback = 5;
            winBonus = 10;
        } else if (level == uint256(VipNFT.VipLevel.PLATINUM)) {
            adjustedMaxBet += 10 ether;
            adjustedHouseFee = 1;
            cashback = 10;
            winBonus = 20;
        }

        return (adjustedMaxBet, adjustedHouseFee, cashback, winBonus);
    }

    /**
     * @notice Allows a player to place multiple bets in a single transaction.
     * @param betOnNumber Whether the player is betting on a specific number.
     * @param number The number chosen by the player (0-36).
     * @param betOnColor Whether the player is betting on color.
     * @param color The chosen color (true = red, false = black).
     * @param betOnGreen Whether the player is betting on green (0).
     * @param betOnEven Whether the player is betting on even numbers.
     * @param betOnOdd Whether the player is betting on odd numbers.
     */
    function placeMultiBet(
        bool betOnNumber, uint8 number,
        bool betOnColor, bool color,
        bool betOnGreen, bool betOnEven, bool betOnOdd
    ) external payable {
        (uint256 adjustedMaxBet, uint256 adjustedHouseFee, uint256 cashback, ) = getVipBenefits(msg.sender);

        require(msg.value >= minBet, BetIsBelowMinimum());
        require(msg.value <= adjustedMaxBet, BetExceedsMaximum());
        require(!(betOnEven && betOnOdd), CannotBetOnBothEVENAndODD());
        require(!(betOnColor && betOnGreen), CannotBetOnColorAndGreenSimultaneously());
        if (betOnNumber) require(number <= 36, InvalidNum());

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash, subscriptionId, requestConfirmations, callbackGasLimit, numWords
        );

        uint256 houseFeeAmount = (msg.value * adjustedHouseFee) / 100;
        houseBank += houseFeeAmount;
        uint256 betAmount = msg.value - houseFeeAmount;

        if (cashback > 0) {
            uint256 cashbackAmount = (msg.value * cashback) / 100;
            (bool success, ) = payable(msg.sender).call{value: cashbackAmount}("");
            require(success, CashBackTransferFailed());
        }

        bets[requestId] = MultiBet(msg.sender, betAmount, betOnNumber, number, betOnColor, color, betOnGreen, betOnEven, betOnOdd);

        emit BetPlaced(requestId, msg.sender, betAmount);
        emit HouseBankUpdated(houseBank);
    }

    /**
     * @notice Chainlink VRF callback function that determines the game result.
     * @param requestId The request ID from Chainlink VRF.
     * @param randomWords The generated random number.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        MultiBet memory bet = bets[requestId];
        uint8 winningNumber = uint8(randomWords[0] % 37);
        bool win = false;
        uint256 payout = 0;

        (, , , uint256 winBonus) = getVipBenefits(bet.player);

        if (bet.betOnNumber && bet.number == winningNumber) payout = bet.amount * (36 + winBonus) / 100;
        else if (bet.betOnColor) payout = bet.amount * (2 + winBonus) / 100;
        else if (bet.betOnGreen && winningNumber == 0) payout = bet.amount * (18 + winBonus) / 100;
        else if (bet.betOnEven && winningNumber % 2 == 0) payout = bet.amount * (2 + winBonus) / 100;
        else if (bet.betOnOdd && winningNumber % 2 != 0) payout = bet.amount * (2 + winBonus) / 100;

        require(payout <= houseBank, NotEnoughFundsInHouseBank());
        (bool success, ) = bet.player.call{value: payout}("");
        require(success, TransferFailed());
        houseBank -= payout;

        emit GameResult(requestId, bet.player, bet.amount, winningNumber, win);
        delete bets[requestId];
    }
}
