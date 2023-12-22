// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155Burnable.sol";
import "./ERC1155Supply.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./AggregatorV3Interface.sol";
import "./IMOSV3.sol";

contract TicketMinter is
    ERC1155,
    Ownable,
    Pausable,
    ERC1155Supply,
    ERC1155Burnable
{
    string public name;
    string public symbol;
    string public contractURI;
    string public baseURI;

    uint256 public paymentTolerance;
    address public treasuryAddress;

    mapping(uint256 => uint256) public price;
    mapping(uint256 => uint256) public capacity;
    mapping(uint256 => bool) public forSale;
    // mapping(address => uint256[]) public hasClaimed;
    mapping(uint256 => address) public revenueAddress;
    mapping(uint256 => uint256) public percentageOverride;

    IMOSV3 public mos;
    AggregatorV3Interface internal priceFeed;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        uint256 _paymentTolerance,
        address _treasuryAddress,
        address _mos,
        address _priceFeed
    ) ERC1155("") {
        name = _name;
        symbol = _symbol;
        contractURI = _contractURI;
        baseURI = _baseURI;
        paymentTolerance = _paymentTolerance;
        treasuryAddress = _treasuryAddress;
        mos = IMOSV3(_mos);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function crossChainMint(
        address _receiveAddress,
        uint256 _id,
        uint256 _quantity,
        int _amount_USD_8DP
    ) external {
        require(msg.sender == address(mos), "No Permission");
        require(forSale[_id]);
        require(totalSupply(_id) + _quantity <= capacity[_id]);
        require(
            _amount_USD_8DP + int(paymentTolerance) >=
                int(price[_id]) * int(_quantity)
        );
        _mint(_receiveAddress, _id, _quantity, "");
    }

    function mint(
        address _receiveAddress,
        uint256 _id,
        uint256 _quantity,
        uint256 _data
    ) public payable {
        int _amount_USD_8DP = ((int)(msg.value) * getLatestPrice()) / 1e18;
        require(forSale[_id]);
        require(totalSupply(_id) + _quantity <= capacity[_id]);
        require(
            _amount_USD_8DP + int(paymentTolerance) >=
                int(price[_id]) * int(_quantity)
        );

        uint256 _percentage = percentageOverride[_id];
        uint256 _toTreasuryAmount = (msg.value * _percentage) / 100;
        uint256 _toRevenueAmount = msg.value - _toTreasuryAmount;

        address _revenueAddress = revenueAddress[_id] == address(0)
            ? treasuryAddress
            : revenueAddress[_id];

        (bool success, ) = payable(treasuryAddress).call{
            value: _toTreasuryAmount
        }("");
        require(success, "Failed to send revenue");

        (success, ) = payable(_revenueAddress).call{value: _toRevenueAmount}(
            ""
        );
        require(success, "Failed to send revenue");

        _mint(_receiveAddress, _id, _quantity, "");
    }

    function airdrop(
        uint256 _id,
        address[] memory _addresses,
        uint256 _quantity
    ) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _mint(_addresses[i], _id, _quantity, "");
        }
    }

    // _amount_USD_8DP 100000000 = 1 USD
    function createTicket(
        uint256 _capacity,
        uint256 _amount_USD_8DP,
        uint256 _id,
        address _revenueAddress,
        uint256 _percentageOverride
    ) public onlyOwner {
        price[_id] = _amount_USD_8DP;
        capacity[_id] = _capacity;
        forSale[_id] = true;
        revenueAddress[_id] = _revenueAddress;
        percentageOverride[_id] = _percentageOverride;
    }

    function setPrice(uint256 _id, uint256 _amount_USD_8DP) public onlyOwner {
        price[_id] = _amount_USD_8DP;
    }

    function setCapacity(uint256 _id, uint256 _capacity) public onlyOwner {
        capacity[_id] = _capacity;
    }

    function setForSale(uint256 _id, bool _forSale) public onlyOwner {
        forSale[_id] = _forSale;
    }

    function setTreasuryAddress(address _treasuryAddress) public onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function setContractURI(string memory _contractURI) public onlyOwner {
        contractURI = _contractURI;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function uri(
        uint256 _tokenid
    ) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(baseURI, Strings.toString(_tokenid), ".json")
            );
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        require(from == address(0) || to == address(0), "Soulbound");
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function setTrustFromAddress(
        uint256 _sourceChainId,
        bytes memory _sourceAddress,
        bool _tag
    ) external onlyOwner {
        mos.addRemoteCaller(_sourceChainId, _sourceAddress, _tag);
    }

    function getTrustFromAddress(
        address _targetAddress,
        uint256 _sourceChainId,
        bytes memory _sourceAddress
    ) external view returns (bool) {
        return
            mos.getExecutePermission(
                _targetAddress,
                _sourceChainId,
                _sourceAddress
            );
    }

    function getLatestPrice() public view returns (int) {
        (, int _price, , , ) = priceFeed.latestRoundData();
        return _price;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        require(_amount <= address(this).balance, "Insufficient balance");
        payable(msg.sender).transfer(_amount);
    }

    function bytesToAddress(
        bytes memory bys
    ) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }
}

