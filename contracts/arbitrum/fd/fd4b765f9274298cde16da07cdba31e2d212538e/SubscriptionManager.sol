// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ICollectionManager.sol";
import "./IEntityRegistry.sol";
import "./IUser.sol";
import "./ISubscriptionManager.sol";
import "./ILoot8Collection.sol";
import "./ILoot8BurnableCollection.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";

contract SubscriptionManager is ISubscriptionManager, Initializable, DAOAccessControlled {
    using SafeERC20 for IERC20;


    mapping(address => SubscriptionConfig) public subscriptionConfig;
    mapping(address => uint256) public passportsSupply;

    IEntityRegistry public entityRegistry;
    IERC20 public loot8Token;
    IUser public userContract;
    address public loot8Wallet;

    modifier whenSubscriptionHasStarted(address passport) {
        require(subscriptionConfig[passport].subscriptionHasStarted, "SUBSCRIPTION NOT STARTED");
        _;
    }

    function initialize(
        address _loot8Token,
        address _loot8Wallet,
        address _daoAuthority,
        address _entityRegistry,
        address _userContract
    ) public initializer {
        loot8Token = IERC20(_loot8Token);
        loot8Wallet = _loot8Wallet;
        entityRegistry = IEntityRegistry(_entityRegistry);
        userContract = IUser(_userContract);
        _setAuthority(_daoAuthority);
    }

    function isValidPassport(address _passport) internal view returns (bool) {
        bool isPassport = ICollectionManager(authority.getAuthorities().collectionManager).getCollectionType(_passport) == ICollectionData.CollectionType.PASSPORT;
        // if (isPassport) {
        //     address _entity = ic.getCollectionData(_passport).entity;
        //     bool isOnboarded = entityRegistry.isOnboardedEntity(_entity);
        //     return isOnboarded;
        // }
        return isPassport;
    }

    function hasValidSubscriptionConfig(address _passport) internal view returns (bool) {
        SubscriptionConfig memory _config = subscriptionConfig[_passport];
        return _config.floorPrice == 0 ? _config.tradingEnabled : (_config.tradingEnabled && _config.platformFeePercent > 0 && _config.peopleFeePercent > 0 && _config.peopleFeeReceiver != address(0));
    }

    function setPassportSubscriptionConfig(
        address passport,
        uint256 _peopleFeePercent,
        uint256 _platformFeePercent,
        address _peopleFeeReceiver,
        uint256 _floorPrice,
        bool _tradingEnabled,
        bool _startSubscriptions
    ) external onlyEntityAdmin(ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(passport).entity) {
        require(isValidPassport(passport), "NOT A VALID PASSPORT");
        subscriptionConfig[passport].peopleFeePercent = _peopleFeePercent;
        subscriptionConfig[passport].platformFeePercent = _platformFeePercent;
        subscriptionConfig[passport].peopleFeeReceiver = _peopleFeeReceiver;
        subscriptionConfig[passport].tradingEnabled = _tradingEnabled;

        if (!subscriptionConfig[passport].subscriptionHasStarted) {
            subscriptionConfig[passport].floorPrice = _floorPrice;
        }

        if (_startSubscriptions) {
            subscriptionConfig[passport].subscriptionHasStarted = true;
        }
        emit SubscriptionConfigSet(passport, _floorPrice, _tradingEnabled, _startSubscriptions);
    }

    function setPriceConfig(
        address passport,
        uint256 floorPrice
    ) external onlyEntityAdmin(ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(passport).entity) {
        require(subscriptionConfig[passport].subscriptionHasStarted == false, "SUBSCRIPTIONS HAVE STARTED");
        subscriptionConfig[passport].floorPrice = floorPrice;
    }

    function startSubscriptions(address passport) external onlyEntityAdmin(ICollectionManager(authority.getAuthorities().collectionManager).getCollectionData(passport).entity) {
        subscriptionConfig[passport].subscriptionHasStarted = true;
    }

    function setTradingEnabled(
        address passport,
        bool _tradingEnabled
    ) external onlyGovernor {
        require(isValidPassport(passport), "NOT A VALID PASSPORT");
        subscriptionConfig[passport].tradingEnabled = _tradingEnabled;
    }

    // formula taken from friend.tech
    function getPrice(uint256 _floorPrice, uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 ) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether / 16000) + (_floorPrice * amount);
    }

    function getBuyPrice(address passport, uint256 amount) public view returns (uint256, uint256, uint256) {
        SubscriptionConfig memory _config = subscriptionConfig[passport];
        if (_config.floorPrice == 0) return (0, 0, 0);
        uint256 price = getPrice(_config.floorPrice, passportsSupply[passport], amount);
        uint256 platformFee = price * _config.platformFeePercent / 1 ether;
        uint256 peopleFee = price * _config.peopleFeePercent / 1 ether;
        return (price, platformFee, peopleFee);
    }

    function getSellPrice(address passport, uint256 amount) public view returns (uint256, uint256, uint256) {
        SubscriptionConfig memory _config = subscriptionConfig[passport];
        if (_config.floorPrice == 0) return (0, 0, 0);
        uint256 price = getPrice(_config.floorPrice, passportsSupply[passport] - amount, amount);
        uint256 platformFee = price * _config.platformFeePercent / 1 ether;
        uint256 peopleFee = price * _config.peopleFeePercent / 1 ether;
        return (price, platformFee, peopleFee);
    }

    function subscribe(address passport, uint256 amount) public whenSubscriptionHasStarted(passport) {
        require(amount > 0, "Amount cannot be zero");
        require(hasValidSubscriptionConfig(passport), "Passport Uninitialized");
        require(userContract.isValidPermittedUser(_msgSender()), "UNAUTHORIZED");

        uint256 supply = passportsSupply[passport];
        SubscriptionConfig memory _config = subscriptionConfig[passport];
        require(_config.tradingEnabled, "Trading disabled");

        uint256 price;
        uint256 platformFee;
        uint256 peopleFee;

        if (_config.floorPrice != 0) {
            (price, platformFee, peopleFee) = getBuyPrice(passport, amount);
            uint256 allowance = loot8Token.allowance(_msgSender(), address(this));
            require(allowance >= price + platformFee + peopleFee, "INSUFFICIENT ALLOWANCE");
            loot8Token.safeTransferFrom(_msgSender(), loot8Wallet, platformFee);
            loot8Token.safeTransferFrom(_msgSender(), _config.peopleFeeReceiver, peopleFee);
            loot8Token.safeTransferFrom(_msgSender(), address(this), price);
        }

        passportsSupply[passport] = supply + amount;
        ILoot8Collection _passport = ILoot8Collection(passport);

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _passport.getNextTokenId();
            _passport.mint(_msgSender(), tokenId);
        }

        emit Trade(_msgSender(), passport, true, amount, price + platformFee + peopleFee);
    }

    function unsubscribe(address passport, uint256[] memory _passportIds) public whenSubscriptionHasStarted(passport) {
        require(_passportIds.length > 0, "Passport IDs required");
        require(hasValidSubscriptionConfig(passport), "Passport Uninitialized");
        require(userContract.isValidPermittedUser(_msgSender()), "UNAUTHORIZED");

        SubscriptionConfig memory _config = subscriptionConfig[passport];
        require(_config.tradingEnabled, "Trading disabled");
        uint256 amount = _passportIds.length;

        for (uint256 i = 0; i < amount; i++) {
            require(
                IERC721(passport).getApproved(_passportIds[i]) == address(this) ||
                IERC721(passport).isApprovedForAll(_msgSender(), address(this)), "UNAUTHORIZED");
            require(
                IERC721(passport)
                    .ownerOf(_passportIds[i]) == _msgSender(),
                "Only Passport owner"
            );
        }

        uint256 price;
        uint256 platformFee;
        uint256 peopleFee;

        if (_config.floorPrice != 0) {
            (price, platformFee, peopleFee) = getSellPrice(passport, amount);
            loot8Token.safeTransfer(_msgSender(), price - platformFee - peopleFee);
            loot8Token.safeTransfer(loot8Wallet, platformFee);
            loot8Token.safeTransfer(subscriptionConfig[passport].peopleFeeReceiver, peopleFee);
        }

        uint256 supply = passportsSupply[passport];
        passportsSupply[passport] = supply - amount;

        for (uint256 i=0; i<_passportIds.length; i++) {
            ILoot8BurnableCollection(passport).burn(_passportIds[i]);
        }

        emit Trade(_msgSender(), passport, false, amount, price + platformFee + peopleFee);
    }
}
