//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract ArbswapAirdrop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;
    // Public address who is backnd singer
    address public signer;

    uint256 public immutable AirdropStartTimestamp;
    uint256 public immutable AirdropEndTimestamp;
    uint256 public immutable VestingDurationOne;
    uint256 public immutable VestingDurationTwo;

    // Record the token amount which have not been released.
    uint256 public totalNotReleasedAmount;

    // Record the token amount which had been released.
    uint256 public totalReleasedAmount;

    // Record the token amount which had been burned.
    uint256 public totalBurnedAmount;

    uint256 public constant PRECISION = 1e12;
    uint256 public constant ETH_AMOUNT = 0.01 ether;
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;
    bytes32 public constant ZERO_BYTE =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    enum ClaimType {
        Pay, // pay ETH to get 50% token, vesting 50%
        Burn, // 1: get 10% , burn 90%.
        Vesting // 2: get 5% , vesting 15% , burn 80%
    }

    struct UserInfo {
        address user;
        bool claimed;
        uint96 amount; // uint96 is enough for airdrop amount.
        uint96 releasedVestingAmount;
        uint32 vestingStartTime;
        uint32 vestingEndTime;
        uint96 burnAmount;
        uint96 vestingAmount;
        uint64 claimType;
    }

    mapping(address => UserInfo) public userInfos;

    error InvalidTime();
    error InvalidETHAmount();
    error InvalidClaimType();
    error AlreadyClaimed();
    error NotOwner();
    error NotVesting();
    error VestingEnd();
    error NotInWhiteList();
    error NotZero();

    event SetSigner(address newSigner);
    event Claim(
        address indexed user,
        ClaimType claimType,
        uint256 amount,
        uint256 transferAmount,
        uint256 burnAmount,
        uint256 vestingAmount
    );
    event Release(address indexed user, uint96 amount);
    event ClaimETH(uint256 amount);
    event ClaimToken(
        address indexed tokenAddress,
        address indexed user,
        uint256 amount
    );

    modifier isValidSign(
        address user,
        uint256 amount,
        bytes memory sign
    ) {
        require(tx.origin == msg.sender, "ContractNotAllowed");
        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(user, amount))
        );
        require(ECDSA.recover(message, sign) == signer, "NotInWhiteList");
        _;
    }

    /**
     * @notice Constructor.
     * @param _token: Token address.
     * @param _startTime: Airdrop start time.
     * @param _endTime: Airdrop end time.
     * @param _vestingDurationOne: Airdrop vesting duration.
     * @param _vestingDurationTwo: Airdrop vesting duration.
     */
    constructor(
        IERC20 _token,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _vestingDurationOne,
        uint256 _vestingDurationTwo
    ) {
        token = _token;
        AirdropStartTimestamp = _startTime;
        AirdropEndTimestamp = _endTime;
        VestingDurationOne = _vestingDurationOne;
        VestingDurationTwo = _vestingDurationTwo;
        signer = 0x689ed9F373a9019374395FbE1C47ACc69B1D2a93;
    }

    /**
     * @notice Claim airdrop token.
     * @param sign: Signed message form backend.
     * @param amount: Airdrop amount.
     * @param claimType: Claim type, 0: pay ETH to get all token, 1: get 10% , burn left, 2:vesting.
     */
    function claim(
        bytes memory sign,
        uint256 amount,
        ClaimType claimType
    ) external payable isValidSign(msg.sender, amount, sign) nonReentrant {
        uint256 currentTime = block.timestamp;
        if (
            currentTime < AirdropStartTimestamp ||
            currentTime > AirdropEndTimestamp
        ) revert InvalidTime();
        UserInfo storage info = userInfos[msg.sender];

        if (info.claimed) revert AlreadyClaimed();

        info.user = msg.sender;
        info.claimed = true;
        info.claimType = uint64(claimType);

        uint256 vestingAmount;
        uint256 burnAmount;
        uint256 transferAmount;
        if (claimType == ClaimType.Pay) {
            // pay ETH to get 50% token, vesting 50%
            if (msg.value != ETH_AMOUNT) revert InvalidETHAmount();
            transferAmount = amount / 2;
            token.safeTransfer(msg.sender, transferAmount);

            // vesting
            vestingAmount = amount - transferAmount;
            info.vestingStartTime = uint32(currentTime);
            info.vestingEndTime = uint32(currentTime + VestingDurationOne);
        } else if (claimType == ClaimType.Burn) {
            // 1: get 10% , burn 90%
            transferAmount = amount / 10;
            token.safeTransfer(msg.sender, transferAmount);

            burnAmount = amount - transferAmount;

            token.transfer(BURN_ADDRESS, burnAmount);
        } else if (claimType == ClaimType.Vesting) {
            // 2: get 5% , vesting 15% , burn 80%
            transferAmount = amount / 20;
            token.safeTransfer(msg.sender, transferAmount);

            // vesting
            vestingAmount = (amount * 3) / 20;
            info.vestingStartTime = uint32(currentTime);
            info.vestingEndTime = uint32(currentTime + VestingDurationTwo);

            burnAmount = amount - transferAmount - vestingAmount;

            token.transfer(BURN_ADDRESS, burnAmount);
        } else {
            revert InvalidClaimType();
        }

        info.amount = uint96(amount);
        info.burnAmount = uint96(burnAmount);
        info.vestingAmount = uint96(vestingAmount);

        totalNotReleasedAmount += vestingAmount;
        totalReleasedAmount += transferAmount;
        totalBurnedAmount += burnAmount;

        emit Claim(
            msg.sender,
            claimType,
            amount,
            transferAmount,
            burnAmount,
            vestingAmount
        );
    }

    /**
     * @notice Release vesting token.
     */
    function release() external nonReentrant {
        UserInfo storage info = userInfos[msg.sender];
        if (msg.sender != info.user) revert NotOwner();

        if (
            info.claimType != uint64(ClaimType.Pay) &&
            info.claimType != uint64(ClaimType.Vesting)
        ) revert NotVesting();

        if (info.releasedVestingAmount >= info.vestingAmount)
            revert VestingEnd();

        uint256 currentTime = block.timestamp;
        if (block.timestamp > info.vestingEndTime) {
            currentTime = info.vestingEndTime;
        }

        uint256 VestingDuration = (info.claimType == uint64(ClaimType.Pay))
            ? VestingDurationOne
            : VestingDurationTwo;
        uint96 releasedVestingAmount = uint96(
            ((currentTime - info.vestingStartTime) * info.vestingAmount) /
                VestingDuration
        );

        if (releasedVestingAmount > info.vestingAmount) {
            releasedVestingAmount = info.vestingAmount;
        }
        releasedVestingAmount -= info.releasedVestingAmount;

        if (releasedVestingAmount > 0) {
            totalNotReleasedAmount -= releasedVestingAmount;

            totalReleasedAmount += releasedVestingAmount;

            info.releasedVestingAmount += releasedVestingAmount;

            token.safeTransfer(msg.sender, uint256(releasedVestingAmount));
            emit Release(msg.sender, releasedVestingAmount);
        }
    }

    /**
     * @notice It allows the owner to claim tokens.
     * @param tokenAddress: token address
     * @dev Callable by owner
     */
    function claimToken(address tokenAddress) external onlyOwner {
        // Can not claim token before airdrop end
        // if (block.timestamp < AirdropEndTimestamp) revert InvalidTime();
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
        uint256 amount;
        if (tokenAddress == address(token)) {
            if (tokenBalance > totalNotReleasedAmount) {
                amount = tokenBalance - totalNotReleasedAmount;
            }
        } else {
            amount = tokenBalance;
        }

        if (amount > 0) {
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
            emit ClaimToken(tokenAddress, msg.sender, amount);
        }
    }

    /**
     * @notice Claim all ETH
     * @dev Callable by owner
     */
    function claimETH() external nonReentrant onlyOwner {
        uint256 amount = address(this).balance;
        _safeTransferETH(msg.sender, amount);

        emit ClaimETH(amount);
    }

    /**
     * @notice Change whitelist message signer
     * @dev Callable by owner
     */
    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit SetSigner(newSigner);
    }

    /**
     * @notice Transfer ETH in a safe way
     * @param to: address to
     * @param value: ETH amount
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) revert();
    }
}

