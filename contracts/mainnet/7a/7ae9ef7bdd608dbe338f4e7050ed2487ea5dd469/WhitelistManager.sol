//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./AccessControl.sol";
import "./SafeMath.sol";
import "./IFarmV2.sol";
import "./IPriceFeed.sol";
import "./IMoneyHandler.sol";
import "./CollectionV2.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";

contract WhitelistManager is AccessControl {
    string private greeting;

    uint256 public startTime;
    uint256 public endTime;
    bytes32 public root;
    address public ernTreasure;
    IMoneyHandler public moneyHand;
    IPriceFeed public priceOracle;
    uint256 public percent;

    mapping(address => CollectionInfo) public collectionInfo;
    address[] public collections;

    struct CollectionInfo {
        IERC20 token;
        uint256 amount;
        IFarmV2 stone;
    }

    event SoldWithStones(address buyer, uint256 amount);
    event PaymentShared(address account, uint256 amount);
    event PaymentTreasure(address account, uint256 amount);
    event Sold(
        address indexed operator,
        address indexed to,
        uint256 indexed id,
        uint256 amount
    );

    constructor(
        address _ernTreasure,
        address _moneyHandler,
        address _priceOracle
    ) {
        moneyHand = IMoneyHandler(_moneyHandler);
        ernTreasure = _ernTreasure;
        percent = 900000000000000000;
        priceOracle = IPriceFeed(_priceOracle);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setStartTime(uint256 _startTime)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        startTime = _startTime;
    }

    function setEndTime(uint256 _endTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
        endTime = _endTime;
    }

    function setRoot(bytes32 _root) public onlyRole(DEFAULT_ADMIN_ROLE) {
        root = _root;
    }

    function setTreasurer(address _ernTreasure)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ernTreasure = _ernTreasure;
    }

    function setMoneyHandler(address _moneyHandler)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        moneyHand = IMoneyHandler(_moneyHandler);
    }

    function setPriceOracle(address _priceOracle)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        priceOracle = IPriceFeed(_priceOracle);
    }

    function setCollections(
        address[] calldata _collections,
        CollectionInfo[] calldata _infos
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _collections.length == _infos.length,
            "Required to have same length"
        );
        for (uint256 i = 0; i < collections.length; i++) {
            delete collectionInfo[collections[i]];
        }
        delete collections;
        for (uint256 i = 0; i < _collections.length; i++) {
            collectionInfo[_collections[i]] = _infos[i];
            collections.push(_collections[i]);
        }
    }

    function isWhitelisted(address _user, bytes32[] calldata proof)
        public
        view
        returns (bool)
    {
        return
            MerkleProof.verify(proof, root, keccak256(abi.encodePacked(_user)));
    }

    function buy(
        address collection,
        uint256 id,
        address buyer,
        bytes32[] calldata proof
    ) external {
        require(_msgSender() == buyer, "Buyer must be equal to msgSender");
        require(isWhitelisted(buyer, proof), "User is not whitelisted");
        require(
            startTime <= block.timestamp && endTime > block.timestamp,
            "Sale did not start yet"
        );
        CollectionInfo memory info = collectionInfo[collection];
        require(
            info.amount != 0 &&
                (address(info.stone) != address(0) ||
                    address(info.token) != address(0)),
            "Collection is not parf of sale"
        );

        address(info.stone) == address(0)
            ? _withToken(buyer, info.token, info.amount, collection)
            : _withStones(buyer, info.stone, info.amount);

        IMintableInterface(collection).mint(buyer, id);

        emit Sold(address(this), buyer, id, info.amount);
    }

    function _withStones(
        address buyer,
        IFarmV2 stone,
        uint256 amount
    ) private {
        uint256 stones = stone.rewardedStones(buyer);
        require(stones >= amount, "You do not have enough points !");
        require(stone.payment(buyer, amount), "Payment was unsuccessful");

        emit SoldWithStones(buyer, amount);
    }

    function calcPerc(uint256 _amount, uint256 _percent)
        private
        pure
        returns (uint256)
    {
        uint256 sellmul = SafeMath.mul(_amount, _percent);
        uint256 sellAmount = SafeMath.div(sellmul, 10**18);
        return sellAmount;
    }

    function _withToken(
        address buyer,
        IERC20 token,
        uint256 amount,
        address collection
    ) private {
        uint256 price = getCardPrice(token, amount);
        require(
            token.balanceOf(buyer) >= price,
            "Insufficient funds: Cannot buy this NFT"
        );

        uint256 treasAmount = calcPerc(price, percent);
        uint256 shareAmount = SafeMath.sub(price, treasAmount);

        token.transferFrom(buyer, address(this), price);
        token.transfer(ernTreasure, treasAmount);
        token.transfer(address(moneyHand), shareAmount);

        moneyHand.updateCollecMny(collection, shareAmount);

        emit PaymentTreasure(collection, treasAmount);
        emit PaymentShared(collection, shareAmount);
    }

    function getTokenPrice(IERC20 token) public view returns (uint256) {
        address tokenFeed = priceOracle.getFeed(address(token));
        int256 priceUSD = priceOracle.getThePrice(tokenFeed);
        uint256 uPriceUSD = uint256(priceUSD);

        return uPriceUSD;
    }

    function getCardPrice(IERC20 token, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 tokenPrice = getTokenPrice(token);
        uint256 result = (amount * (1e44)) / (tokenPrice * (1e18));

        return result;
    }
}

