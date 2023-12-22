// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./ERC1155URIStorageUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./IWETH.sol";
import "./IACLManager.sol";
import "./IProfitDistributor.sol";

contract Tickets is ERC1155BurnableUpgradeable, ERC1155SupplyUpgradeable, ERC1155URIStorageUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using StringsUpgradeable for uint256;

    IWETH public WETH;
    IACLManager public aclManager;
    address public profitDistributor;

    mapping(uint256 => mapping(uint256 => uint256)) public prices;
    mapping(address => mapping(uint256 => uint256)) public bidsBalance;
    mapping(address => mapping(uint256 => uint256)) public bidsProfit;
    mapping(uint256 => uint256) public totalBalance;
    mapping(uint256 => uint256) public minPrices;

    event SetPrice(uint256 indexed id, uint256 amount, uint256 price);
    event ResetPrice(uint256 indexed id);
    event SetProfitDistributor(address indexed _profitDistributor);

    event AddProfit(address indexed bidsPool, uint256 amount);

    event WithdrawWETH(
        address indexed bidsPool,
        address indexed to,
        uint256 indexed id,
        uint256 amount
    );

    event WithdrawProfit(
        address indexed bidsPool,
        address indexed to,
        uint256 indexed id,
        uint256 amount
    );

    event ClaimWETH(
        address indexed to,
        uint256 indexed id,
        uint256 amount
    );

    modifier onlyBids() {
        require(aclManager.isBidsContract(msg.sender), "ONLY_BIDS_CONTRACT");
        _;
    }

    modifier onlyGovernance() {
        require(aclManager.isGovernance(msg.sender), "ONLY_GOVERNANCE");
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(aclManager.isEmergencyAdmin(msg.sender), "ONLY_EMERGENCY_ADMIN");
        _;
    }

    // constructor(
    //     string memory _uri,
    //     address weth,
    //     address _aclManager,
    //     address _profitDistributor
    // ) ERC1155(_uri) Ownable() Pausable() {
    //     WETH = IWETH(weth);
    //     aclManager = IACLManager(_aclManager);
    //     profitDistributor = _profitDistributor;
    // }

    function initialize(
        string memory _uri,
        address _weth,
        address _aclManager,
        address _profitDistributor
    ) initializer public {
        __ERC1155_init(_uri);
        __Ownable_init();
        __Pausable_init();

        WETH = IWETH(_weth);
        aclManager = IACLManager(_aclManager);
        profitDistributor = _profitDistributor;
    }

    function pause() external onlyEmergencyAdmin {
        _pause();
    }

    function unpause() external onlyEmergencyAdmin {
        _unpause();
    }

    function setPrice(
        uint256 id,
        uint256 amount,
        uint256 price
    ) external onlyGovernance {
        _setPrice(id, amount, price);
    }

    function _setPrice(uint256 id, uint256 amount, uint256 price) internal {
        prices[id][amount] = price;
        uint256 avgPrice = price / amount;
        if (minPrices[id] == 0 || avgPrice < minPrices[id]) {
            minPrices[id] = avgPrice;
        }

        emit SetPrice(id, amount, price);
    }

    function resetMinPrice(uint256 id) external onlyGovernance {
        minPrices[id] = 0;

        emit ResetPrice(id);
    }

    function setBaseURI(string memory newBaseUri) external onlyOwner {
        _setBaseURI(newBaseUri);
    }

    function setURI(uint256 tokenId, string memory tokenURI) external onlyOwner {
        _setURI(tokenId, tokenURI);
    }

    function uri(uint256 tokenId) public view virtual override(ERC1155Upgradeable, ERC1155URIStorageUpgradeable) returns (string memory) {
        return super.uri(tokenId);
    }

    function setProfitDistributor(address _profitDistributor) external onlyGovernance {
        _setProfitDistributor(_profitDistributor);
    }

    function _setProfitDistributor(address _profitDistributor) internal {
        profitDistributor = _profitDistributor;

        emit SetProfitDistributor(_profitDistributor);
    }

    function getFullPrice(uint256 id) public view returns (uint256) {
        require(prices[id][1] != 0, "PRICE_ERROR");
        return prices[id][1];
    }

    function getPrice(
        uint256 id,
        uint256 amount
    ) public view returns (uint256) {
        return prices[id][amount];
    }

    function getMinPrice(uint256 id) public view returns (uint256) {
        return minPrices[id];
    }

    function getBidsBalance(address bids, uint256 id) public view returns (uint256) {
        return bidsBalance[bids][id];
    }

    function mintWhenBidding(
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external payable onlyBids whenNotPaused {
        _mint(msg.sender, id, amount, data);

        totalBalance[id] += msg.value;
        WETH.deposit{value: msg.value}();
    }

    function mintWithETH(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external payable whenNotPaused {
        uint256 price = prices[id][amount];
        require(price > 0, "AMOUNT_NOT_ALLOWED");
        require(price <= msg.value, "ETH_AMOUNT_INSUFFICIENT");
        _mint(to, id, amount, data);

        totalBalance[id] += price;

        WETH.deposit{value: price}();

        if (price < msg.value) {
            AddressUpgradeable.sendValue(payable(msg.sender), msg.value - price);
        }
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external whenNotPaused {
        uint256 price = prices[id][amount];
        require(price > 0, "AMOUNT_NOT_ALLOWED");
        WETH.transferFrom(msg.sender, address(this), price);
        _mint(to, id, amount, data);
        totalBalance[id] += price;
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external whenNotPaused {
        uint256 payAmount;
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 price = prices[ids[i]][amounts[i]];
            require(price > 0, "AMOUNT_NOT_ALLOWED");
            payAmount += price;
            totalBalance[ids[i]] += price;
        }
        WETH.transferFrom(msg.sender, address(this), payAmount);
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address sender, uint256 id, uint256 amount) public override onlyBids {
        super.burn(sender, id, amount);

        uint256 price = amount * getMinPrice(id);
        bidsBalance[msg.sender][id] += price;

        totalBalance[id] -= price;
    }

    function addProfit(uint256 id, uint256 amount) external onlyBids {
        bidsProfit[msg.sender][id] += amount;
        emit AddProfit(msg.sender, amount);
    }

    function withdrawWETH(uint256 id, uint256 amount) external onlyBids {
        _withdrawWETH(msg.sender, msg.sender, id, amount);
    }

    function _withdrawWETH(address bids, address to, uint256 id, uint256 amount) internal {
        require(bidsBalance[bids][id] >= amount, "INSUFFICIENT_BALANCE");

        bidsBalance[bids][id] -= amount;

        WETH.transfer(to, amount);
        emit WithdrawWETH(bids, to, id, amount);
    }

    function withdrawProfit(address bids, uint256 id, uint256 amount) external onlyGovernance {
        require(profitDistributor != address(0), "UNSET_PROFIT_DISTRIBUTOR");
        require(bidsProfit[bids][id] >= amount, "INSUFFICIENT_PROFIT");

        bidsProfit[bids][id] -= amount;
        bidsBalance[bids][id] -= amount;

        WETH.approve(profitDistributor, amount);
        IProfitDistributor(profitDistributor).distribute(address(WETH), amount);

        emit WithdrawProfit(bids, profitDistributor, id, amount);
    }

    function claimWETH(uint256 id, uint256 amount) external onlyGovernance {
        require(profitDistributor != address(0), "UNSET_PROFIT_DISTRIBUTOR");
        require(getAvailableBalance(id) >= amount, "NOT_ALLOWED_AMOUNT");

        totalBalance[id] -= amount;

        WETH.approve(profitDistributor, amount);
        IProfitDistributor(profitDistributor).distribute(address(WETH), amount);

        emit ClaimWETH(profitDistributor, id, amount);
    }

    function getAvailableBalance(uint256 id) public view returns (uint256) {
        return totalBalance[id] - totalSupply(id) * getMinPrice(id);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

