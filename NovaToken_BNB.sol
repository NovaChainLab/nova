// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NovaToken is ERC20, Ownable, ReentrancyGuard {
    uint8 public constant DECIMALS = 8;
    uint256 public constant MIN_STAKE_AMOUNT = 1 * (10 ** 8);
    uint256 public constant REWARD_PERCENT = 20;
    uint256 public constant NUM_WEEKS = 21;
    uint256 public constant NUM_DAYS = NUM_WEEKS * 7;
    uint256 public constant SECONDS_PER_DAY = 86400;

    uint256 public constant MAX_TOTAL_SUPPLY = 100_000_000 * (10 ** DECIMALS);


    uint256 public totalClaimedReward;

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimedDay;
        uint256 dailyReward;
        uint256 claimedReward;
    }

    struct StakeDetails {
        bytes32 depositHash;
        uint256 amount;
        uint256 startTime;
        uint256 claimedReward;
    }

    mapping(address => bytes32[]) private userStakeHashes;
    mapping(bytes32 => StakeInfo) private stakes;
    mapping(bytes32 => address) public stakeToOwner;
    bytes32[] public allStakeHashes;

    event StakeCreated(
        address indexed user,
        uint256 amount,
        bytes32 indexed depositHash
    );
    event RewardClaimed(
        bytes32 indexed depositHash,
        address indexed user,
        uint256 amount
    );

    event Minted(address indexed to, uint256 amount);

    constructor() ERC20("NOVA", "NOVA") Ownable(msg.sender) {
        _transferOwnership(msg.sender);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        require(
            totalSupply() + amount <= MAX_TOTAL_SUPPLY,
            "Minting would exceed total supply"
        );

        _mint(to, amount);
        emit Minted(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    function stakeNova(uint256 amount) public {
        require(
            amount >= MIN_STAKE_AMOUNT,
            "Stake amount must be at least 1 tokens"
        );
        require(amount <= balanceOf(msg.sender), "Insufficient balance");
        require(msg.sender != address(0), "stakeNova Invalid recipient");

        _transfer(msg.sender, address(this), amount);

        uint256 reward = (amount * REWARD_PERCENT) / 100;

        require(
            totalSupply() + reward <= MAX_TOTAL_SUPPLY,
            "Minting reward would exceed total supply"
        );
        _mint(address(this), reward);

        uint256 totalDistribute = amount + reward;

        uint256 daily = totalDistribute / NUM_DAYS;

        bytes32 depositHash = keccak256(
            abi.encodePacked(
                msg.sender,
                amount,
                block.timestamp,
                userStakeHashes[msg.sender].length
            )
        );

        uint256 startDay = block.timestamp / SECONDS_PER_DAY;
        stakes[depositHash] = StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            lastClaimedDay: startDay - 1,
            dailyReward: daily,
            claimedReward: 0
        });

        stakeToOwner[depositHash] = msg.sender;
        userStakeHashes[msg.sender].push(depositHash);
        allStakeHashes.push(depositHash);

        emit StakeCreated(msg.sender, amount, depositHash);
    }

    function claimDailyReward(
        bytes32 depositHash
    ) public nonReentrant returns (uint256) {
        StakeInfo storage stake = stakes[depositHash];
        require(stakeToOwner[depositHash] == msg.sender, "Not stake owner");
        require(stake.amount >= MIN_STAKE_AMOUNT, "Invalid stake");
        require(msg.sender != address(0), "claimDailyReward Invalid recipient");

        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        uint256 startDay = stake.startTime / SECONDS_PER_DAY;
        uint256 endDay = startDay + NUM_DAYS;

        if (currentDay >= endDay) {
            revert("Claim period expired");
        }

        uint256 daysToClaim = currentDay - stake.lastClaimedDay;
        if (daysToClaim == 0) {
            revert("Already claimed today");
        }

        uint256 toClaim = stake.dailyReward * daysToClaim;

        require(
            balanceOf(address(this)) >= toClaim,
            "Insufficient reward pool"
        );

        stake.lastClaimedDay = currentDay;
        stake.claimedReward += toClaim;
        totalClaimedReward += toClaim;

        _transfer(address(this), msg.sender, toClaim);

        emit RewardClaimed(depositHash, msg.sender, toClaim);

        return stake.claimedReward;
    }

    function canClaimToday(bytes32 depositHash) public view returns (bool) {
        StakeInfo memory stake = stakes[depositHash];
        if (stakeToOwner[depositHash] != msg.sender || stake.amount == 0)
            return false;

        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        uint256 startDay = stake.startTime / SECONDS_PER_DAY;

        return
            (currentDay < startDay + NUM_DAYS) &&
            (currentDay > stake.lastClaimedDay);
    }

    function getUserStakeList(
        address user
    ) public view returns (StakeDetails[] memory) {
        bytes32[] memory hashes = userStakeHashes[user];
        StakeDetails[] memory details = new StakeDetails[](hashes.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            StakeInfo memory stake = stakes[hashes[i]];
            details[i] = StakeDetails({
                depositHash: hashes[i],
                amount: stake.amount,
                startTime: stake.startTime,
                claimedReward: stake.claimedReward
            });
        }
        return details;
    }
}
