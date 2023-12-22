// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
pragma abicoder v2;

// import "hardhat/console.sol";
import {AccessControl} from "./AccessControl.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
// import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {ERC721Template} from "./ERC721Template.sol";

contract MintNftFactoryV2 is Ownable, ReentrancyGuard {
    uint256 public constant ONE_HUNDRED_PERCENT = 100 * 100; // 100%
    uint256 public constant MAX_PERCENT_AFF = 5000; // 50%

    address public royaltyAddress;
    // value fee to ETH
    uint256 public royaltyFee;

    uint256 public totalPool = 0;

    mapping(address => bool) public admins;

    // poolId => nft address
    mapping(uint256 => address) public containerNfts;
    // nft address => priceNft
    mapping(address => uint256) public mapPrice;

    // nft address => address manager
    mapping(address => address) public managers;
    // nft address => time end
    mapping(address => uint256) public endTimes;

    // nft address => max allocation mint
    mapping(address => uint256) public maxTotalSupplys;

    // nft address => max allocation mint
    mapping(address => uint256) public maxAllocationPerUsers;

    // nft address => percent shared aff
    mapping(address => uint256) public percentAffs;

    // nft address => percent shared aff by system
    mapping(address => uint256) public systemPercentAffs;

    // nft address => partner address => is shared system fee
    mapping(address => mapping(address => bool)) public partnerAffs;

    // nft address => user address => qty minteds
    mapping(address => mapping(address => uint256)) public minteds;

    // nft address => promotionQty
    mapping(address => uint256[]) public promotionQtys;

    // nft address => promotionPercent
    mapping(address => uint256[]) public promotionPercents;

    event DeployNft(uint256 poolId, address nftAddress, address manager);

    modifier onlyAdmin() {
        require(admins[_msgSender()], "Admin: caller is not the admin");
        _;
    }

    modifier validatePercentAff(uint256 _percentAff) {
        require(_percentAff <= MAX_PERCENT_AFF, "Percent AFF over");
        _;
    }

    modifier verifyManager(address _nft) {
        require(managers[_nft] != address(0), "Nft not config manager");
        require(managers[_nft] == _msgSender(), "Account is not manager");
        _;
    }

    constructor(address _royaltyAddress, uint256 _royaltyFee) {
        require(
            _royaltyAddress != address(0),
            "Royalty Address is Zero address"
        );
        royaltyAddress = _royaltyAddress;
        royaltyFee = _royaltyFee;
        admins[_msgSender()] = true;
    }

    function updateAdmin(
        address _admin,
        bool _isAdd
    ) external onlyAdmin nonReentrant {
        require(_admin != address(0), "Admin address is Zero ");
        admins[_admin] = _isAdd;
    }

    function deploy(
        string memory _name,
        string memory _symbol,
        string memory _baseUrlNft,
        uint256 _priceNft, // price by ETH
        uint256 _endTime,
        uint256 _maxTotalSupply, // if(=0)   unlimited
        uint256 _maxAllocationPerUser, // if(=0)   unlimited
        uint256 _percentAff // if(=0) not set
    )
        external
        nonReentrant
        validatePercentAff(_percentAff)
        returns (uint256 poolId, address nftAddress)
    {
        // create NFT
        totalPool++;
        ERC721Template nft = new ERC721Template(_name, _symbol, _baseUrlNft);
        containerNfts[totalPool] = address(nft);
        mapPrice[address(nft)] = _priceNft;
        managers[address(nft)] = msg.sender;
        endTimes[address(nft)] = _endTime;
        maxTotalSupplys[address(nft)] = _maxTotalSupply;
        maxAllocationPerUsers[address(nft)] = _maxAllocationPerUser;
        percentAffs[address(nft)] = _percentAff;
        emit DeployNft(totalPool, address(nft), msg.sender);
        return (totalPool, address(nft));
    }

    function mint(
        address _nft,
        address _ref
    ) external payable nonReentrant returns (uint256 tokenId) {
        require(managers[_nft] != address(0), "Nft not config manager");
        require(block.timestamp <= endTimes[_nft], "Time mint ended");

        if (maxTotalSupplys[_nft] != 0) {
            require(
                maxTotalSupplys[_nft] > ERC721Template(_nft).totalSupply(),
                "Qty over max total supply"
            );
        }

        if (maxAllocationPerUsers[_nft] != 0) {
            require(
                minteds[_nft][msg.sender] < maxAllocationPerUsers[_nft],
                "User over allocation minted"
            );
        }

        uint256 amount = mapPrice[_nft] + royaltyFee;
        require(msg.value >= amount, "Not enough amount to mint");

        minteds[_nft][msg.sender] += 1;
        uint256 amountAffPrice;
        uint256 amountAffSystem;
        if (_ref != address(0)) {
            if (percentAffs[_nft] > 0 && mapPrice[_nft] > 0) {
                amountAffPrice =
                    (mapPrice[_nft] * percentAffs[_nft]) /
                    ONE_HUNDRED_PERCENT;
            }
            if (systemPercentAffs[_nft] > 0 && partnerAffs[_nft][_ref]) {
                amountAffSystem =
                    (royaltyFee * systemPercentAffs[_nft]) /
                    ONE_HUNDRED_PERCENT;
            }
        }

        if (amountAffPrice + amountAffSystem > 0) {
            payable(_ref).transfer(amountAffPrice + amountAffSystem);
        }
        if (mapPrice[_nft] - amountAffPrice > 0) {
            payable(managers[_nft]).transfer(mapPrice[_nft] - amountAffPrice);
        }
        payable(royaltyAddress).transfer(royaltyFee - amountAffSystem);
        tokenId = ERC721Template(_nft).mint(address(msg.sender));
        return tokenId;
    }

    function getPromotionPercentByQty(
        address _nft,
        uint256 _qty
    ) public view returns (uint256) {
        if (
            promotionQtys[_nft].length == 0 ||
            promotionPercents[_nft].length == 0
        ) {
            return 0;
        }
        for (uint i = 0; i < promotionQtys[_nft].length; i++) {
            if (promotionQtys[_nft][i] <= _qty) {
                return promotionPercents[_nft][i];
            }
        }
        return 0;
    }

    // mint and check Promotion
    function mintByQty(
        address _nft,
        uint256 _qty,
        address _ref
    ) external payable nonReentrant returns (uint256[] memory tokenIds) {
        require(managers[_nft] != address(0), "Nft not config manager");
        require(block.timestamp <= endTimes[_nft], "Time mint ended");
        if (maxTotalSupplys[_nft] != 0) {
            require(
                maxTotalSupplys[_nft] >
                    ERC721Template(_nft).totalSupply() + _qty,
                "Qty over max total supply"
            );
        }

        if (maxAllocationPerUsers[_nft] != 0) {
            require(
                minteds[_nft][msg.sender] + _qty < maxAllocationPerUsers[_nft],
                "User over allocation minted"
            );
        }

        uint256 systemFeeAmount = royaltyFee * _qty;
        uint256 principalAmount = mapPrice[_nft] * _qty;

        uint256 promotionalAmount = principalAmount -
            (principalAmount * getPromotionPercentByQty(_nft, _qty)) /
            ONE_HUNDRED_PERCENT;

        require(
            msg.value >= promotionalAmount + systemFeeAmount,
            "Not enough amount to mint"
        );

        minteds[_nft][msg.sender] += 1;
        uint256 amountAffPrice;
        uint256 amountAffSystem;
        if (_ref != address(0)) {
            if (percentAffs[_nft] > 0 && mapPrice[_nft] > 0) {
                amountAffPrice =
                    (principalAmount * percentAffs[_nft]) /
                    ONE_HUNDRED_PERCENT;
            }
            if (systemPercentAffs[_nft] > 0 && partnerAffs[_nft][_ref]) {
                amountAffSystem =
                    (systemFeeAmount * systemPercentAffs[_nft]) /
                    ONE_HUNDRED_PERCENT;
            }
        }

        if (amountAffPrice + amountAffSystem > 0) {
            payable(_ref).transfer(amountAffPrice + amountAffSystem);
        }
        if (promotionalAmount - amountAffPrice > 0) {
            payable(managers[_nft]).transfer(
                promotionalAmount - amountAffPrice
            );
        }
        payable(royaltyAddress).transfer(systemFeeAmount - amountAffSystem);
        tokenIds = ERC721Template(_nft).mintBatch(address(msg.sender), _qty);
        return tokenIds;
    }

    function changeSystemPercentAff(
        address _nft,
        uint256 _percentAff
    ) external nonReentrant onlyAdmin validatePercentAff(_percentAff) {
        systemPercentAffs[_nft] = _percentAff;
    }

    function updatePartnerAff(
        address _nft,
        address[] calldata _partners,
        bool _isAdd
    ) external nonReentrant onlyAdmin {
        for (uint i = 0; i < _partners.length; i++) {
            partnerAffs[_nft][_partners[i]] = _isAdd;
        }
    }

    function changeManager(
        address _nft,
        address _newManager
    ) external nonReentrant verifyManager(_nft) {
        require(_newManager != address(0), "New manager invalid address");
        managers[_nft] = _newManager;
    }

    function changePercentAff(
        address _nft,
        uint256 _percentAff
    )
        external
        nonReentrant
        verifyManager(_nft)
        validatePercentAff(_percentAff)
    {
        percentAffs[_nft] = _percentAff;
    }

    function changePriceNft(
        address _nft,
        uint256 _priceNft
    ) external nonReentrant verifyManager(_nft) {
        mapPrice[_nft] = _priceNft;
    }

    // default qty from large to small
    function changePromotion(
        address _nft,
        uint256[] calldata _qtys,
        uint256[] calldata _percents
    ) external nonReentrant verifyManager(_nft) {
        require(_qtys.length == _percents.length, "Invalid inputs");
        delete promotionQtys[_nft];
        delete promotionPercents[_nft];
        for (uint i = 0; i < _qtys.length; i++) {
            // max percent promotion 30%
            require(_percents[i] <= 3000, "Percent promotion over 30%");
            promotionQtys[_nft].push(_qtys[i]);
            promotionPercents[_nft].push(_percents[i]);
        }
    }

    function changeEndTime(
        address _nft,
        uint256 _endTime
    ) external nonReentrant verifyManager(_nft) {
        endTimes[_nft] = _endTime;
    }

    function changeMaxTotalSupply(
        address _nft,
        uint256 _maxTotalSupply
    ) external nonReentrant verifyManager(_nft) {
        if (_maxTotalSupply != 0) {
            require(
                _maxTotalSupply >= ERC721Template(_nft).totalSupply(),
                "Max total under total supply minted"
            );
        }
        maxTotalSupplys[_nft] = _maxTotalSupply;
    }

    function changeRoyaltyAddress(
        address _royaltyAddress
    ) external nonReentrant {
        require(
            royaltyAddress == msg.sender || msg.sender == owner(),
            "Address not permisson change royalty address"
        );
        royaltyAddress = _royaltyAddress;
    }

    function changeRoyaltyFee(uint256 _royaltyFee) external nonReentrant {
        require(
            royaltyAddress == msg.sender || msg.sender == owner(),
            "Address not permisson change royalty fee"
        );
        royaltyFee = _royaltyFee;
    }

    function getAmountOut(
        address _nft
    ) public view returns (uint256 amountOut) {
        amountOut = mapPrice[_nft] + royaltyFee;
        return amountOut;
    }

    function getAmountOutByQty(
        address _nft,
        uint256 _qty
    ) public view returns (uint256 amountOut) {
        uint256 systemFeeAmount = royaltyFee * _qty;
        uint256 principalAmount = mapPrice[_nft] * _qty;
        uint256 promotionalAmount = principalAmount -
            (principalAmount * getPromotionPercentByQty(_nft, _qty)) /
            ONE_HUNDRED_PERCENT;
        return promotionalAmount + systemFeeAmount;
    }

    function getPromotionAmountByQty(
        address _nft,
        uint256 _qty
    ) public view returns (uint256) {
        uint256 principalAmount = mapPrice[_nft] * _qty;
        uint256 promotionalAmount = principalAmount -
            (principalAmount * getPromotionPercentByQty(_nft, _qty)) /
            ONE_HUNDRED_PERCENT;
        return promotionalAmount;
    }

    function getPromotionQtys(
        address _nft
    ) public view returns (uint256[] memory) {
        return promotionQtys[_nft];
    }

    function getPromotionPercents(
        address _nft
    ) public view returns (uint256[] memory) {
        return promotionPercents[_nft];
    }
}

