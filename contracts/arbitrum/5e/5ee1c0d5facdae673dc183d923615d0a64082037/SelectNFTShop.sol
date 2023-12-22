// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./SelectNFT.sol";
import "./Ownable.sol";

struct Beneficiary {
    address payoutAddress;
    uint16 basisPoints;
}

struct SaleData {
    uint128 projectId;
    uint64  maxSupply;
    uint64  maxPerTx;
    uint64  maxPerWallet;
    uint64  startTime;
    uint128 price;
}

contract SelectNFTShop is Ownable {
    SelectNFT private selectNFT;

    uint256 public nextSaleId;
    mapping(uint256 => SaleData) public sales;
    mapping(uint256 => uint256) public saleSupply;
    mapping(uint256 => Beneficiary[]) public saleBeneficiaries;
    mapping(uint256 => mapping(address => uint256)) private mintCount;

    function setSelectNFT(SelectNFT nft) public onlyOwner {
        selectNFT = nft;
    }

    function createSale(
        uint128 _projectId, 
        uint64 _maxSupply, 
        uint64 _maxPerTx, 
        uint64 _maxPerWallet, 
        uint64 _startTime, 
        uint128 _price,
        Beneficiary[] calldata _beneficiaries
    )
        public
        onlyOwner
    {
        setBeneficiaries(nextSaleId, _beneficiaries);
        sales[nextSaleId++] = SaleData(_projectId, _maxSupply, _maxPerTx, _maxPerWallet, _startTime, _price);
    }

    function setBeneficiaries(uint256 _saleId, Beneficiary[] calldata _beneficiaries) public onlyOwner {
        delete saleBeneficiaries[_saleId];

        uint16 totalBasisPoints;
        for (uint256 idx = 0; idx < _beneficiaries.length; idx++) {
            totalBasisPoints += _beneficiaries[idx].basisPoints;
            saleBeneficiaries[_saleId].push(_beneficiaries[idx]);
        }
        
        require(totalBasisPoints <= 10000, "SelectShop: basis points > 100%");
    }

    function setSalePrice(uint256 _saleId, uint128 _price) public onlyOwner {
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");
        sales[_saleId].price = _price;
    }

    function setSaleStartTime(uint256 _saleId, uint64 _startTime) public onlyOwner {
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");
        sales[_saleId].startTime = _startTime;
    }

    function setSaleMaxSupply(uint256 _saleId, uint64 _maxSupply) public onlyOwner {
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");
        sales[_saleId].maxSupply = _maxSupply;
    }

    function setSaleMaxPerTx(uint256 _saleId, uint64 _maxPerTx) public onlyOwner {
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");
        sales[_saleId].maxPerTx = _maxPerTx;
    }

    function setSaleMaxPerWallet(uint256 _saleId, uint64 _maxPerWallet) public onlyOwner {
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");
        sales[_saleId].maxPerWallet = _maxPerWallet;
    }

    function canBuy(address _who, uint256 _saleId, uint256 _cnt) public view returns(bool) {
        SaleData memory sale = sales[_saleId];
        return (sale.maxSupply == 0 || saleSupply[_saleId] + _cnt < sale.maxSupply)
            && (sale.maxPerTx == 0 || _cnt <= sale.maxPerTx)
            && (sale.maxPerWallet == 0 || mintCount[_saleId][_who] + _cnt <= sale.maxPerWallet);
    }

    function buy(uint256 _saleId, uint256 _cnt) public payable {
        require(_cnt > 0, "SelectShop: must mint at least 1");
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");

        SaleData memory sale = sales[_saleId];
        require(sale.startTime != 0 && block.timestamp >= sale.startTime, "SelectShop: sale has not started");
        require(msg.value == sale.price * _cnt, "SelectShop: cannot cover mint costs");
        require(sale.maxSupply == 0 || saleSupply[_saleId] + _cnt < sale.maxSupply, "SelectShop: sale is sold out");
        require(sale.maxPerTx == 0 || _cnt <= sale.maxPerTx, "SelectShop: mint exceeds maxPerTx");
        require(sale.maxPerWallet == 0 || mintCount[_saleId][msg.sender] + _cnt <= sale.maxPerWallet, "SelectShop: mint exceeds maxPerWallet");

        Beneficiary[] memory beneficiaries = saleBeneficiaries[_saleId];
        if (beneficiaries.length > 0) {
            for (uint256 idx = 0; idx < beneficiaries.length; idx++) {
                Beneficiary memory beneficiary = beneficiaries[idx];
                uint256 payout = msg.value * beneficiary.basisPoints / 10000;
                (bool success,) = beneficiary.payoutAddress.call{value: payout}("");
                require(success, "SelectShop: transfer to beneficiary failed");
            }
        }

        saleSupply[_saleId] += _cnt;
        mintCount[_saleId][msg.sender] += _cnt;

        for (uint256 i = 0; i < _cnt; i++) {
            selectNFT.mint(msg.sender, sale.projectId);
        }
    }

    function buyFor(address _to, uint256 _saleId, uint256 _cnt) public onlyOwner {
        require(_cnt > 0, "SelectShop: must mint at least 1");
        require(_saleId < nextSaleId, "SelectShop: sale does not exist");

        SaleData memory sale = sales[_saleId];
        require(sale.startTime != 0 && block.timestamp >= sale.startTime, "SelectShop: sale has not started");
        require(sale.maxSupply == 0 || saleSupply[_saleId] + _cnt < sale.maxSupply, "SelectShop: sale is sold out");
        require(sale.maxPerTx == 0 || _cnt <= sale.maxPerTx, "SelectShop: mint exceeds maxPerTx");
        require(sale.maxPerWallet == 0 || mintCount[_saleId][_to] + _cnt <= sale.maxPerWallet, "SelectShop: mint exceeds maxPerWallet");

        saleSupply[_saleId] += _cnt;
        mintCount[_saleId][_to] += _cnt;

        for (uint256 i = 0; i < _cnt; i++) {
            selectNFT.mint(_to, sale.projectId);
        }
    }

    function withdrawAll() public onlyOwner {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "SelectShop: transfer failed");
    }
}

