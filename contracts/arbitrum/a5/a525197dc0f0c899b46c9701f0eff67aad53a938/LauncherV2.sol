// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IConfig.sol";
import "./IShares.sol";
import "./ILauncher.sol";
import "./IAuthenticate.sol";
import "./IMakeFriendCoin.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./SignatureChecker.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract LauncherV2 is ILauncher, Initializable, UUPSUpgradeable {
    IConfig public immutable config;
    address public operator;
    IMakeFriendCoin public mfc;
    IERC20 public acceptedToken;

    mapping(address => bool) blackList;
    mapping(address => uint256) share2MultiplyAmount;
    mapping(address => bool) acceptedShare2Multiply;

    mapping(address => uint256) userBuyAmount;
    mapping(uint256 tgId => uint256) userEranAmount;
    mapping(address => uint256) userBuyPrice;

    uint256 public remainSharePoolAmount;

    uint256 public remainBuyAmount;
    uint256 public maxBuyAmount;
    uint256 public maxEarnAmount;
    // Here we do not restrict the chainId, this is to allow users to authenticate only once for all chains
    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );
    bytes32 private constant LAUNCHER_DOMAIN_SEPARATOR_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant _USER_EARN_MINT_TX_TYPEHASH =
        keccak256("UserEarn(address user,uint256 tgId,uint256 earnTotal)");

    function _userEarnHash(UserEarn memory ue) private view returns (bytes32) {
        return
            _hashTypedData(
                keccak256(
                    abi.encode(
                        _USER_EARN_MINT_TX_TYPEHASH,
                        ue.user,
                        ue.tgId,
                        ue.earnTotal
                    )
                )
            );
    }

    /// EIP712
    function _getDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    LAUNCHER_DOMAIN_SEPARATOR_TYPEHASH,
                    block.chainid,
                    address(this)
                )
            );
    }

    /// @notice Creates an EIP-712 typed data hash
    function _hashTypedData(bytes32 dataHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _getDomainSeparator(), dataHash)
            );
    }

    modifier onlyMFC() {
        require(address(mfc) == msg.sender, "Launcher: caller is not the mfc");
        _;
    }

    modifier onlyOwner() {
        require(
            config.owner() == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor(IConfig _config) {
        config = _config;
    }

    function initialize(
        address _operator,
        IMakeFriendCoin _mfc,
        IERC20 _acceptedToken
    ) public initializer {
        __UUPSUpgradeable_init();
        operator = _operator;
        remainSharePoolAmount = 10_000_000_000 * 10 ** 18;
        remainBuyAmount = 5_000_000_000 * 1e18;
        maxBuyAmount = 1_000_000 * 1e18;
        maxEarnAmount = 960_000 * 1e18;
        mfc = _mfc;
        acceptedToken = _acceptedToken;
    }

    function setOperator(address operator_) external onlyOwner {
        operator = operator_;
    }

    function getRemainSharePoolAmount()
        external
        view
        override
        returns (uint256)
    {
        return remainSharePoolAmount;
    }

    function getShare2MultiplyAmount(
        address shareId
    ) external view override returns (uint256) {
        return share2MultiplyAmount[shareId];
    }

    function getRemainBuyAmount(address to) public view returns (uint256) {
        return Math.min(remainBuyAmount, maxBuyAmount - userBuyAmount[to]);
    }

    function getRemainEarnAmount(uint256 tgId) public view returns (uint256) {
        return
            Math.min(
                maxEarnAmount - userEranAmount[tgId],
                remainSharePoolAmount
            );
    }

    function getPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = 5_000_000_000 * 1e18 - remainBuyAmount;
        return getPrice(supply, amount);
    }

    function getPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        uint256 price0 = 0;
        uint256 fp = 100_000_000_000_000 * 1e18;
        if (supply > 0) {
            price0 = (50_000 * supply);
        }
        uint256 price1 = (50_000 * (supply + amount + 1e18));
        return
            Math.ceilDiv(
                Math.mulDiv(price1 + price0, amount, 2) + fp * amount,
                1e48
            );
    }

    function launchDone() public view override returns (bool) {
        return remainBuyAmount == 0;
    }

    function subShare2MultiplyAmount(
        address from,
        address to,
        uint256 amount,
        uint256 rewardAmoumt
    ) external onlyMFC {
        acceptedShare2Multiply[to] = true;
        share2MultiplyAmount[from] -= amount;
        remainSharePoolAmount -= amount;
        emit AcceptedShare2Earn(from, to, amount, rewardAmoumt);
    }

    function getTribeShare2MultiplyRemainTimes(
        address shareId
    ) external view override returns (uint256) {
        if (acceptedShare2Multiply[shareId]) {
            return 0;
        }
        return 1;
    }

    function computeShare2EarnReward(
        address from,
        address to,
        uint256 amount
    ) external view override returns (uint256) {
        // share_token * (1 + 0.1 * (my tribe member - 2) +  0.2 * (friend tribe member - 2) )
        IShares shares = IShares(config.getShares());
        // from
        uint256 fromMemberCount = shares.members(from, 0);
        uint256 toMemberCount = shares.members(to, 0);
        if (fromMemberCount >= 2) {
            fromMemberCount = Math.max(fromMemberCount - 2, 1);
        }
        if (toMemberCount >= 2) {
            toMemberCount = Math.max(toMemberCount - 2, 1);
        }
        uint256 reward = amount +
            Math.mulDiv(amount, (fromMemberCount + toMemberCount * 2), 10);
        return Math.min(reward, remainSharePoolAmount);
    }

    function getMaxHoldeAmount() external pure override returns (uint256) {
        return 4_000_000 * 1e18;
    }

    function isAuthorized(
        address shareId
    ) external view override returns (bool) {
        IAuthenticate authenticate = IAuthenticate(config.getAuthenticate());
        return authenticate.isAuthorized(shareId);
    }

    /// mint
    function getEarnClaimable(
        UserEarn memory ue
    ) public view returns (uint256) {
        uint256 amount = Math.min(
            getRemainEarnAmount(ue.tgId),
            ue.earnTotal - userEranAmount[ue.tgId]
        );
        return amount;
    }

    function earnMint(UserEarn memory ue, bytes memory signature) external {
        // check signature
        bytes32 dataHash = _userEarnHash(ue);
        require(
            SignatureChecker.isValidSignatureNow(operator, dataHash, signature),
            "Launcher: invalid signature"
        );
        uint256 mintAmount = getEarnClaimable(ue);
        userEranAmount[ue.tgId] += mintAmount;
        remainSharePoolAmount -= mintAmount;
        share2MultiplyAmount[ue.user] += mintAmount;
        mfc.mint(ue.user, mintAmount);
        emit EarnMFC(ue.user, mintAmount);
    }

    function buy(address to, uint256 amount, uint256 maxPrice) external {
        require(remainBuyAmount > 0, "Launcher: buy amount is zero");
        require(
            amount <= getRemainBuyAmount(to),
            "Launcher: buy amount exceeds max buy amount"
        );
        uint256 price = getPrice(amount);
        require(price <= maxPrice, "Launcher: price exceeds max price");
        acceptedToken.transferFrom(msg.sender, address(this), price);
        userBuyPrice[to] += price;
        userBuyAmount[to] += amount;
        share2MultiplyAmount[to] += amount;
        remainBuyAmount -= amount;
        mfc.mint(to, amount);
        emit BuyMFC(to, amount, price);
    }

    /// black list --- ///

    function isBlackList(
        address account
    ) external view override returns (bool) {
        return blackList[account];
    }

    function setBlackList(address account, bool isBlack) external onlyOwner {
        blackList[account] = isBlack;
    }

    function withdrawLPToken() external {
        require(launchDone(), "Launcher: launch not done");
        address to = config.owner();
        acceptedToken.transfer(to, acceptedToken.balanceOf(address(this)));
        mfc.mint(to, 5_000_000_000 * 1e18);
    }

    /// upgrade --- ///
    function getInitializedVersion() external view returns (uint8) {
        return _getInitializedVersion();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}

