// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./VipNFT.sol";

/**
 * @title Coinflip Smart Contract
 * @notice A decentralized coinflip game with VIP NFT integration and Chainlink VRF random number generation.
 * @dev This contract allows users to place bets, receive winnings, and benefit from VIP NFT perks.
 */
contract Coinflip is VRFConsumerBaseV2, Ownable {
    VRFCoordinatorV2Interface private immutable COODRINATOR;
    VipNFT public immutable vipNft;

    //Custom error messages
    error BetExceedsMaximum();
    error BetIsBelowMinimum();
    error CashBackTransferFailed();
    error WithdrawFailed();
    error InsufficientBank();
    error NotEnoughFundsInBank();
    error InvalidGuess();
    error PayoutFailed();
    error OnlyCoordinatorAllowed();
    error OnlyVRFCoordinatorCanFulfill();
    error MinimumBetMustBeLessThanMaximumBet();

    // Chainlink VRF parameters
    uint64 private immutable subscriptionId;
    address private immutable vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; 
    bytes32 private immutable keyHash;
    uint32 private constant callbackGasLimit = 200000;
    uint16 private constant requestConfirmations = 3;
    uint32 private constant numWords = 1;

    // Betting parameters
    uint256 public minBet = 0.001 ether;
    uint256 public maxBet = 5 ether;
    uint256 public houseBank;
    uint256 public houseFee = 5;

    struct Game {
        address player;
        uint256 bet;
        uint8 guess;
        uint timestamp;
    }

    mapping (uint256 => Game) private games;

    // Events
    event BetPlaced(uint256 requestId, address indexed player, uint256 amount);
    event GameResult(uint256 requestId, address indexed player, uint256 amount, uint8 winningNumber, bool win);
    event HouseBankUpdated(uint256 newBalance);

    /** 
     * @notice Initializes the Coinflip contract with Chainlink VRF and VIP NFT contract.
     * @param _subscriptionId Chainlink VRF subscription ID.
     * @param _vipNFT Address of the VIP NFT contract.
     */
    constructor(uint64 _subscriptionId, address _vipNFT) VRFConsumerBaseV2(vrfCoordinator) Ownable(msg.sender) {
        COODRINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
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
     * @notice Places a bet in the Coinflip game.
     * @dev Checks if the bet amount is within the allowed range and sends the bet amount to the Chainlink VRF coordinator.
     */
    function placeBet(uint8 guess) external payable {
        require(guess == 0 || guess == 1, InvalidGuess());

        (uint256 adjustedMaxBet, uint256 adjustedHouseFee, uint256 cashback, ) = getVipBenefits(msg.sender);

        require(msg.value >= minBet, BetIsBelowMinimum());
        require(msg.value <= adjustedMaxBet, BetExceedsMaximum());

        uint256 requestId = COODRINATOR.requestRandomWords(
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

        games[requestId] = Game(msg.sender, betAmount, guess, block.timestamp);

        emit BetPlaced(requestId, msg.sender, betAmount);
        emit HouseBankUpdated(houseBank);
    }

    /**
     * @notice Processes the random number generated by Chainlink VRF.
     * @param requestId The request ID.
     * @param randomWords The random number generated by Chainlink VRF.
     */
   function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        require(msg.sender == address(COODRINATOR), OnlyCoordinatorAllowed());

        Game memory game = games[requestId];
        delete games[requestId];

        uint8 result = uint8(randomWords[0] % 2);
        bool win = (result == game.guess); 

        (, , , uint256 winBonus) = getVipBenefits(game.player);

        uint256 payout = 0;
        if (win) {
            payout = game.bet * (200 + winBonus) / 100;

            require(payout <= houseBank, NotEnoughFundsInBank());

            (bool success, ) = payable(game.player).call{value: payout}("");
            require(success, PayoutFailed());

            houseBank -= payout;
        }

        emit GameResult(requestId, game.player, game.bet, result, win);
        emit HouseBankUpdated(houseBank);
    }


    /**
     * @notice Sets the minimum and maximum bet limits.
     * @param _min The minimum bet limit.
     * @param _max The maximum bet limit.
     */
    function SetLimits(uint256 _min, uint256 _max) external onlyOwner {
        require(_min < _max, MinimumBetMustBeLessThanMaximumBet());
        minBet = _min;
        maxBet = _max;
    }

    function withdraw(address payable _to, uint256 amount) external onlyOwner {
        require(amount <= houseBank, InsufficientBank());
        houseBank -= amount;
        (bool success, ) = _to.call{value: amount}("");
        require(success, WithdrawFailed());
        emit HouseBankUpdated(houseBank);
    }

    receive() external payable {
        houseBank += msg.value;
        emit HouseBankUpdated(houseBank);
    }
}