// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./Interfaces.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./draft-IERC20Permit.sol";

/**
 * @author Heisenberg
 * @notice Buffer Options Router Contract
 */
contract Booster is Ownable, IBooster, AccessControl {
    using SafeERC20 for ERC20;

    ITraderNFT nftContract;
    uint16 public MAX_TRADES_PER_BOOST = 0;
    uint256 public couponPrice;
    uint256 public boostPercentage;
    bytes32 public constant OPTION_ISSUER_ROLE =
        keccak256("OPTION_ISSUER_ROLE");
    address admin;

    mapping(address => mapping(address => UserBoostTrades))
        public userBoostTrades;
    mapping(uint8 => uint8) public nftTierDiscounts;

    constructor(address _nft) {
        nftContract = ITraderNFT(_nft);
        admin = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setConfigure(
        uint8[4] calldata _nftTierDiscounts
    ) external onlyOwner {
        for (uint8 i; i < 4; i++) {
            nftTierDiscounts[i] = _nftTierDiscounts[i];
        }
    }

    function getNftTierDiscounts() external view returns (uint8[4] memory) {
        uint8[4] memory _nftTierDiscounts;
        for (uint8 i; i < 4; i++) {
            _nftTierDiscounts[i] = nftTierDiscounts[i];
        }
        return _nftTierDiscounts;
    }

    function getUserBoostData(
        address user,
        address token
    ) external view override returns (UserBoostTrades memory) {
        return userBoostTrades[token][user];
    }

    function updateUserBoost(
        address user,
        address token
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        UserBoostTrades storage userBoostTrade = userBoostTrades[token][user];
        userBoostTrade.totalBoostTradesUsed += 1;
        emit UpdateBoostTradesUser(user, token);
    }

    function getBoostPercentage(
        address user,
        address token
    ) external view override returns (uint256) {
        UserBoostTrades memory userBoostTrade = userBoostTrades[token][user];
        if (
            userBoostTrade.totalBoostTrades >
            userBoostTrade.totalBoostTradesUsed
        ) {
            return boostPercentage;
        } else return 0;
    }

    function setPrice(uint256 price) external onlyOwner {
        couponPrice = price;
        emit SetPrice(couponPrice);
    }

    function setBoostPercentage(uint256 boost) external onlyOwner {
        boostPercentage = boost;
        emit SetBoostPercentage(boost);
    }

    function approveViaSignature(
        address tokenX,
        address user,
        Permit memory permit
    ) internal {
        IERC20Permit token = IERC20Permit(tokenX);
        uint256 nonceBefore = token.nonces(user);
        token.permit(
            user,
            address(this),
            permit.value,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        uint256 nonceAfter = token.nonces(user);
        if (nonceAfter != nonceBefore + 1) {
            revert("Nonce didn't match");
        }
        emit ApproveTokenX(
            user,
            nonceBefore,
            permit.value,
            permit.deadline,
            tokenX
        );
    }

    function buy(
        address tokenAddress,
        uint256 traderNFTId,
        address user,
        Permit memory permit,
        uint256 coupons
    ) external onlyOwner {
        ERC20 token = ERC20(tokenAddress);

        uint256 discount;
        if (nftContract.tokenOwner(traderNFTId) == user)
            discount =
                (couponPrice *
                    coupons *
                    nftTierDiscounts[
                        nftContract.tokenTierMappings(traderNFTId)
                    ]) /
                100;
        uint256 price = (couponPrice * coupons) - discount;
        require(token.balanceOf(user) >= price, "Not enough balance");
        if (permit.shouldApprove) {
            approveViaSignature(tokenAddress, user, permit);
        }
        token.safeTransferFrom(user, admin, price);
        userBoostTrades[tokenAddress][user].totalBoostTrades +=
            MAX_TRADES_PER_BOOST *
            coupons;
        emit BuyCoupon(tokenAddress, user, price);
    }
}

