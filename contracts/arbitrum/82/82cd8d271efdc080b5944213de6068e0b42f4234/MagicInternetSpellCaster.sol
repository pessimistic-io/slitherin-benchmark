// SPDX-License-Identifier: MIT
import {IUniswapV3FlashCallback} from "./IUniswapV3FlashCallback.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {PoolAddress} from "./PoolAddress.sol";
import {SafeMath} from "./SafeMath.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
pragma solidity ^0.8.20;

interface IMIFREN {
    function getTokenId() external view returns (uint256);
    function getmiXP(uint256 tokenId) external view returns (uint256);
    function getmiHP(uint256 tokenId) external view returns (uint256); // Add this line
    function ownerOf(uint256 tokenId) external view returns (address);
    function setmiXP(uint256 tokenId, uint256 _miXP) external;
    function setmiHP(uint256 tokenId, uint256 _miHP) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function isCauldronInRange(address fren) external returns (bool);
    function withdraw(uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function getFrenId(address _fren) external returns (uint256);

    function getIdFren(uint256 _id) external returns (address);
    function setTimeStamp(address fren, uint256 _lastSpellTimeStamp) external;

    function getSpellTimeStamp(address fren) external returns (uint256);
}

interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface IMiCauldron {
    event PositionDeposited(uint256 indexed tokenId, address indexed from, address indexed to);
    struct StakedPosition {
        uint256 tokenId;
        uint128 liquidity;
        uint256 stakedAt;
        uint256 lastRewardTime;
    }

    function withdrawPosition(uint256 tokenId) external;
    function pendingRewards(address user) external view returns (uint256 rewards);
    function claimRewards() external;
    function drinkHealPotion() external;
    function drinkProtectPotion() external;
    function decreaseLiquidity(uint128 liquidity) external returns (uint amount0, uint amount1);
    function _getStakedPositionID(address fren) external returns (uint256 tokenId);
    function swapETH_Half(uint value, bool isWETH) external payable returns (uint amountOut);
    function brewManaFromETH()
        external
        payable
        returns (uint _tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund0, uint refund1);
    function isCauldronInRange(address fren) external view returns (bool);

    function _rebalancePosition(address fren, address refund) external returns (uint _refund0, uint _refund1);
    function increasePosition(
        address fren,
        uint _amountMana,
        uint _amountWETH
    ) external returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund0, uint refund1);
}

contract MagicInternetSpells {
    IMIFREN public nftContract;
    IMIFREN public miMana;
    address public auth;
    mapping(address => bool) public isAuth;
    mapping(address => uint256) public lastSpellTimestamp;

    constructor(address _nftContract, address _mimana) {
        nftContract = IMIFREN(_nftContract);
        miMana = IMIFREN(_mimana);
    }

    event SpellResult(address indexed sender, address indexed target, bool success, uint256 amount);
    modifier onlyAuth() {
        require(msg.sender == auth || isAuth[msg.sender], "Caller is not the authorized");
        _;
    }

    function setIsAuth(address fren, bool isAuthorized) external onlyAuth {
        isAuth[fren] = isAuthorized;
    }

    function gibXP(address fren, uint256 amount) internal {
        uint256 tokenId = nftContract.getFrenId(fren);
        uint256 currXP = nftContract.getmiXP(tokenId);
        currXP += amount;

        nftContract.setmiXP(tokenId, currXP);
    }

    function takeHP(address fren, uint256 amount) internal {
        uint256 tokenId = nftContract.getFrenId(fren);
        uint256 currHP = nftContract.getmiHP(tokenId);
        currHP -= amount;

        nftContract.setmiHP(tokenId, currHP);
    }

    uint256 public initialHpFactor = 1; // Default value, can be updated
    uint256 public hpFactor = 10; // Default value, can be updated
    uint256 public amountOfmiManaToKill = 3333000000000000000000; // Default value, can be updated

    function setHpFactor(uint256 _newHpFactor) external onlyAuth {
        require(_newHpFactor > 0, "hpFactor must be greater than zero");
        hpFactor = _newHpFactor;
    }

    function setMiManaToKill(uint256 _newMiMana) external onlyAuth {
        require(_newMiMana > 0, "_newMiMana must be greater than zero");
        amountOfmiManaToKill = _newMiMana;
    }

    function castSpell(address to, uint256 amount) public {
        // Ensure the sender has not cast a spell in the past 5 minutes
        require(
            block.timestamp - lastSpellTimestamp[msg.sender] >= 5 minutes,
            "You can cast only one spell in each 5 minutes."
        );

        // Ensure the target hasn't been spelled in the past 15 minutes
        require(
            block.timestamp - lastSpellTimestamp[to] >= 15 minutes,
            "The target has been spelled in the last 15 minutes."
        );

        // Update the last spell timestamp for the sender
        lastSpellTimestamp[msg.sender] = block.timestamp;

        // Transfer mana cost from the sender to this contract
        miMana.transferFrom(msg.sender, address(this), amount);

        // Calculate HP deduction based on target's experience points
        //uint256 targetXP = nftContract.getmiXP(nftContract.getFrenId(to));
        uint256 hpToDeduct;

        // Calculate HP deduction using the formula amount / targetXP * hpFactor
        hpToDeduct = (amount * hpFactor) / amountOfmiManaToKill;

        // Randomly determine if the spell succeeds (50% chance)
        bool spellSuccess = (uint256(blockhash(block.number - 1)) % 2 == 0);

        if (spellSuccess) {
            // Spell succeeded
            gibXP(msg.sender, amount);
            takeHP(to, hpToDeduct);
        }

        // Emit the SpellResult event
        emit SpellResult(msg.sender, to, spellSuccess, amount);

        // Update the last spell timestamp for the target
        lastSpellTimestamp[to] = block.timestamp;
    }

    function getTokensOrderedByXP() external view returns (uint256[] memory, address[] memory, uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](nftContract.getTokenId());
        address[] memory owners = new address[](tokenIds.length);
        uint256[] memory miHPs = new uint256[](tokenIds.length); // Add this line
        uint256[] memory miXPs = new uint256[](tokenIds.length); // Add this line

        // Copy all token IDs to the array
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = i;
            owners[i] = nftContract.ownerOf(i);
            miHPs[i] = nftContract.getmiHP(i); // Add this line
            miXPs[i] = nftContract.getmiXP(i); // Add this line
        }

        // Bubble sort the token IDs based on XP points
        for (uint256 i = 0; i < tokenIds.length - 1; i++) {
            for (uint256 j = 0; j < tokenIds.length - i - 1; j++) {
                if (nftContract.getmiXP(tokenIds[j]) < nftContract.getmiXP(tokenIds[j + 1])) {
                    // Swap token IDs
                    (tokenIds[j], tokenIds[j + 1]) = (tokenIds[j + 1], tokenIds[j]);
                    // Swap owners accordingly
                    (owners[j], owners[j + 1]) = (owners[j + 1], owners[j]);
                    // Swap miHPs accordingly
                    (miHPs[j], miHPs[j + 1]) = (miHPs[j + 1], miHPs[j]);
                    (miXPs[j], miXPs[j + 1]) = (miXPs[j + 1], miXPs[j]);
                }
            }
        }

        return (tokenIds, owners, miHPs); // Update this line
    }
}

