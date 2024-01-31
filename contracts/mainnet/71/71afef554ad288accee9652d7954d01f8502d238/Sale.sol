//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./OwnableUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./libraries_Helper.sol";
import "./interfaces_IProject.sol";
import "./interfaces_IOSB721.sol";
import "./interfaces_IOSB1155.sol";
import "./interfaces_ISale.sol";
import "./interfaces_INFTChecker.sol";
import "./interfaces_ISetting.sol";

contract Sale is ReentrancyGuardUpgradeable, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable {
    uint256 public constant WEIGHT_DECIMAL = 1e6;
    uint256 public lastId;
    IProject public project;
	INFTChecker public nftChecker;
    ISetting public setting;

    /**
     * @dev Keep track of Sale from saleId
     */
    mapping(uint256 => SaleInfo) public sales;

    /**
     * @dev Keep track of merkleRoot from saleId
     */
    mapping(uint256 => bytes32) public merkleRoots;

    /**
     * @dev Keep track of saleIds of Project from projectId
     */
    mapping(uint256 => uint256[]) private saleIdsOfProject;

    /**
     * @dev Keep track of all buyers of Sale from saleId
     */
    mapping(uint256 => address[]) private buyers;

    /**
     * @dev Keep track of buyers waiting distribution from saleId
     */
    mapping(uint256 => address[]) private buyersWaitingDistributions;

    /**
     * @dev Keep track of buyer bought from saleId and buyer address
     */
    mapping(uint256 => mapping(address => bool)) private bought;

    /**
     * @dev Keep track of bill from saleId and buyer address
     */
    mapping(uint256 => mapping(address => Bill)) private bills;

    /// ============ EVENTS ============

    /// @dev Emit an event when created Sales
    event Creates(uint256 indexed projectId, SaleInfo[] sales);

    /// @dev Emit an event when bought
    event Buy(address indexed buyer, uint256 indexed saleId, uint256 indexed tokenId, uint256 amount, uint256 percentAdminFee, uint256 adminFee, uint256 royaltyFee, uint256 valueForUser, uint256 residualPrice);
    
    /// @dev Emit an event when the status close a Sale is updated
    event SetCloseSale(uint256 indexed saleId, bool status);
    
    /// @dev Emit an event when the amount a Sale is updated
    event SetAmountSale(uint256 indexed saleId, uint256 indexed oldAmount, uint256 indexed newAmount);

    /// @dev Emit an event when the MerkleRoot a Sale is updated
    event SetMerkleRoot(uint256 indexed saleId, bytes32 rootHash);

    /**
     * @notice Setting states initial when deploy contract and only called once
     * @param _setting Setting contract address
     * @param _nftChecker NFTChecker contract address
     */
    function initialize(address _setting, address _nftChecker) external initializer {
        require(_setting != address(0), "Invalid setting");
        require(_nftChecker != address(0), "Invalid nftChecker");
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();
        nftChecker = INFTChecker(_nftChecker);
        setting = ISetting(_setting);
    }

    /**
     * @notice Only called once to set the Project contract address
     * @param _project Project contract address
     */
    function setProjectAddress(address _project) external {
        require(_project != address(0) && address(project) == address(0), "Invalid project");
        project = IProject(_project);
    }

    /// ============ ACCESS CONTROL/SANITY MODIFIERS ============

    /**
     * @dev To check caller is manager
     */
    modifier onlyManager(uint256 _projectId) {
        require(project.isManager(_projectId, _msgSender()), "Caller is not the manager");
        _;
    }

    /**
     * @dev To check caller is controller
     */
    modifier onlyController(address _caller) {
        setting.checkOnlyController(_caller);
        _;
    }

    /**
     * @dev To check caller is Project contract
     */
    modifier onlyProject() {
        require(_msgSender() == address(project), "Caller is not the Project");
        _;
    }

    /**
     * @dev To check Sale is valid
     */
    modifier saleIsValid(uint256 _saleId) {
        require(_saleId > 0 && _saleId <= lastId, "Invalid sale");
        require(!sales[_saleId].isSoldOut, "Sold out");

        ProjectInfo memory _project = project.getProject(sales[_saleId].projectId); 
        uint64 timestamp = uint64(block.timestamp);

        require(_project.status == ProjectStatus.STARTED, "Project inactive");
        require(timestamp >= _project.saleStart, "Sale is not start");
        require(timestamp <= _project.saleEnd, "Sale end");
        _;
    }

    /// ============ FUNCTIONS FOR ONLY PROJECT CONTRACT =============

    /**
     * @notice Create sales sent from Project contract
     * @param _caller address user request
     * @param _isCreateNewToken is create new a token
     * @param _isSetRoyalty is set royalty for token
     * @param _projectInfo project info
     * @param _saleInputs sales inputs
     */
    function creates(address _caller, bool _isCreateNewToken, bool _isSetRoyalty, ProjectInfo memory _projectInfo, SaleInput[] memory _saleInputs) external nonReentrant onlyProject returns (uint256) {
        require(_saleInputs.length > 0, "Invalid param");
        _projectInfo.isSingle ? 
        IOSB721(_projectInfo.token).setApprovalForAll(address(project), true) : 
        IOSB1155(_projectInfo.token).setApprovalForAll(address(project), true);
        
        uint256 id = lastId;
        uint256 totalAmount;

        SaleInfo[] memory _sales = new SaleInfo[](_saleInputs.length);
        for (uint256 i; i < _saleInputs.length; i++) {
            totalAmount += _projectInfo.isSingle ? 1 : _saleInputs[i].amount;
            _sales[i] = _createSale(_caller, ++id, _isCreateNewToken, _isSetRoyalty, _projectInfo, _saleInputs[i]);
        }

        lastId = id;
        emit Creates(_projectInfo.id, _sales);
        return totalAmount;
    }

    /**
     * @notice Support create sale
     * @param _caller address user request
     * @param _saleId sale ID
     * @param _isCreateNewToken is create new a token
     * @param _isSetRoyalty is set royalty for token
     * @param _project project info
     * @param _saleInput sale input
     */
    function _createSale(address _caller, uint256 _saleId, bool _isCreateNewToken, bool _isSetRoyalty, ProjectInfo memory _project, SaleInput memory _saleInput) private returns (SaleInfo memory) {
        if (!_project.isSingle) require(_saleInput.amount > 0, "Invalid amount");

        if (!_project.isFixed) {
            require(_saleInput.maxPrice > _saleInput.minPrice && _saleInput.minPrice > 0, "Invalid price");
            require(_saleInput.priceDecrementAmt > 0 && _saleInput.priceDecrementAmt <= _saleInput.maxPrice - _saleInput.minPrice, "Invalid price");
        }

        SaleInfo storage sale = sales[_saleId];
        sale.id = _saleId;
        sale.projectId = _project.id;
        sale.token = _project.token;
        sale.tokenId = _saleInput.tokenId;
        sale.amount = _project.isSingle ? 1 : _saleInput.amount;
        sale.dutchMaxPrice = _saleInput.maxPrice;
        sale.dutchMinPrice = _saleInput.minPrice;
        sale.priceDecrementAmt = _saleInput.priceDecrementAmt;
        sale.fixedPrice = _saleInput.fixedPrice;
        saleIdsOfProject[_project.id].push(_saleId);

        if (_project.isSingle) {
            if (_isCreateNewToken) {
                sale.tokenId = _isSetRoyalty ? 
                IOSB721(_project.token).mintWithRoyalty(address(this), _saleInput.royaltyReceiver, _saleInput.royaltyFeeNumerator) : 
                IOSB721(_project.token).mint(address(this));
            } else {
                IOSB721(_project.token).safeTransferFrom(_caller, address(this), _saleInput.tokenId);
            }
        } else {
            if (_isCreateNewToken) {
                sale.tokenId = _isSetRoyalty ? 
                IOSB1155(_project.token).mintWithRoyalty(address(this), _saleInput.amount, _saleInput.royaltyReceiver, _saleInput.royaltyFeeNumerator) : 
                IOSB1155(_project.token).mint(address(this), _saleInput.amount);
            } else {
                IOSB1155(_project.token).safeTransferFrom(_caller, address(this), _saleInput.tokenId, _saleInput.amount, "");
            }
        }

        return sale;
    }

    /**
     * @notice Distribute NFTs to buyers waiting or transfer remaining NFTs to project owner and close sale
     * @param _closeLimit loop limit
     * @param _project project info
     * @param _sale sale info
     * @param _totalBuyersWaitingDistribution total buyers waiting distribution
     * @param _totalSalesClose total Sales close
     * @param _isGive NFTs is give
     */
    function close(uint256 _closeLimit, ProjectInfo memory _project, SaleInfo memory _sale, uint256 _totalBuyersWaitingDistribution, uint256 _totalSalesClose, bool _isGive) external onlyProject nonReentrant returns (uint256, uint256) {
        address[] memory buyersWaiting = getBuyersWaitingDistribution(_sale.id);
        for (uint256 i; i < buyersWaiting.length; i++) {
            _totalBuyersWaitingDistribution++;
            Bill memory billInfo = getBill(_sale.id, buyersWaiting[buyersWaiting.length - (i + 1)]);
            uint256 profitShare = billInfo.royaltyFee + billInfo.superAdminFee + billInfo.sellerFee;
            uint256 moneyPaid = _isGive || _project.sold < _project.minSales ? profitShare : 0;
            if (moneyPaid > 0) Helper.safeTransferNative(billInfo.account, moneyPaid);

            else if (!_project.isInstantPayment || _project.sold >= _project.minSales && _project.minSales > 0) {
                Helper.safeTransferNative(billInfo.royaltyReceiver, billInfo.royaltyFee);
                Helper.safeTransferNative(setting.getSuperAdmin(), billInfo.superAdminFee);
                Helper.safeTransferNative(project.getManager(_project.id), billInfo.sellerFee);
            }

            address receiver;
            receiver = (_project.minSales > 0 && _project.sold < _project.minSales && !_isGive) ? _project.manager : billInfo.account;
            
            _project.isSingle ? 
            IOSB721(_project.token).safeTransferFrom(address(this), receiver, _sale.tokenId) : 
            IOSB1155(_project.token).safeTransferFrom(address(this), receiver, _sale.tokenId, billInfo.amount, "");

            buyersWaitingDistributions[_sale.id].pop();
            if (getBuyersWaitingDistribution(_sale.id).length == 0) {
                _totalSalesClose++;
                sales[_sale.id].isClose = true;
            }
            if (_totalBuyersWaitingDistribution == _closeLimit) break;
        }

        return (_totalBuyersWaitingDistribution, _totalSalesClose);
    }

    /**
     * @notice Set ended sale
     * @param _saleId from sale ID
     */
    function setCloseSale(uint256 _saleId) external onlyProject {
        sales[_saleId].isClose = true;
        emit SetCloseSale(_saleId, true);
    }

    /**
     * @notice Update new amount NFTs from sale ID
     * @param _saleId from sale ID
     * @param _amount new amount
     */
    function setAmountSale(uint256 _saleId, uint256 _amount) external onlyProject {
        uint256 oldAmount = sales[_saleId].amount;
        sales[_saleId].amount = _amount;
        emit SetAmountSale(_saleId, oldAmount, _amount);
    }

    /// ============ FUNCTIONS FOR ONLY CONTROLLER =============

    /**
     * @notice Update new MerkleRoot from sale ID
     * @param _saleId from sale ID
     * @param _rootHash new MerkleRoot
     */
    function setMerkleRoot(uint256 _saleId, bytes32 _rootHash) external onlyController(_msgSender()) {
        require(_saleId <= lastId, "Invalid sale");
        merkleRoots[_saleId] = _rootHash;
        emit SetMerkleRoot(_saleId, _rootHash);
    }

    /// ============ OTHER FUNCTIONS =============

    /**
     * @notice Show current dutch price of sale
     * @param _saleId from sale ID
     */ 
    function getCurrentDutchPrice(uint256 _saleId) public view returns (uint256) {
        if (_saleId == 0 || _saleId > lastId) return 0;
        
        ProjectInfo memory _project = project.getProject(sales[_saleId].projectId); 
        uint256 decrement = (sales[_saleId].dutchMaxPrice - sales[_saleId].dutchMinPrice) / sales[_saleId].priceDecrementAmt;
        uint256 timeToDecrementPrice = (_project.saleEnd - _project.saleStart) / decrement;

        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= _project.saleStart) return sales[_saleId].dutchMaxPrice;

        uint256 numDecrements = (currentTimestamp - _project.saleStart) / timeToDecrementPrice;
        uint256 decrementAmt = sales[_saleId].priceDecrementAmt * numDecrements;

        if (decrementAmt > sales[_saleId].dutchMaxPrice || sales[_saleId].dutchMaxPrice - decrementAmt <= sales[_saleId].dutchMinPrice) {
            return sales[_saleId].dutchMinPrice;
        }

        return sales[_saleId].dutchMaxPrice - decrementAmt;
    }

    /**
     * @notice Show all sale IDs from project ID
     * @param _projectId from project ID
     */ 
    function getSaleIdsOfProject(uint256 _projectId) public view returns (uint256[] memory) {
        return saleIdsOfProject[_projectId];
    }     

    /**
     * @notice Show all addresses of buyers waiting for distribution from sale ID
     * @param _saleId from sale ID
     */ 
    function getBuyersWaitingDistribution(uint256 _saleId) public view returns (address[] memory) {
        return buyersWaitingDistributions[_saleId];       
    }

    /**
     * @notice Show the bill info of the buyer
     * @param _saleId from sale ID
     * @param _buyer buyer address
     */ 
    function getBill(uint256 _saleId, address _buyer) public view returns (Bill memory) {
        return bills[_saleId][_buyer];
    }

    /**
     * @notice Show royalty info on the token
     * @param _projectId from project ID
     * @param _tokenId token ID
     * @param _salePrice sale price
     */ 
	function getRoyaltyInfo(uint256 _projectId, uint256 _tokenId, uint256 _salePrice) public view returns (address, uint256) { 
        ProjectInfo memory _project = project.getProject(_projectId);
        if (nftChecker.isImplementRoyalty(_project.token)) {
            (address receiver, uint256 amount) = _project.isSingle ? 
            IOSB721(_project.token).royaltyInfo(_tokenId, _salePrice) : 
            IOSB1155(_project.token).royaltyInfo(_tokenId, _salePrice);

            if (receiver == address(0)) return (address(0), 0);
            return (receiver, amount);
        }
		return (address(0), 0);
	}
    
    /**
     * @notice Show royalty fee
     * @param _projectId from project ID
     * @param _tokenIds token ID
     * @param _salePrices sales prices
     */ 
    function getTotalRoyalFee(uint256 _projectId, uint256[] memory _tokenIds, uint256[] memory _salePrices) public view returns (uint256) {
		uint256 total;
		ProjectInfo memory _project = project.getProject(_projectId);
        if (_project.id == 0) return 0;

        for (uint256 i; i < _tokenIds.length; i++) {
            (, uint256 royaltyAmount) = _project.isSingle ? 
            IOSB721(_project.token).royaltyInfo(_tokenIds[i], _salePrices[i]) : 
            IOSB1155(_project.token).royaltyInfo(_tokenIds[i], _salePrices[i]);
            total += royaltyAmount;
        }
		return total;
	}

    /**
     * @notice Show sales info from project ID
     * @param _projectId from project ID
     */ 
    function getSalesProject(uint256 _projectId) external view returns (SaleInfo[] memory) {
        uint256[] memory saleIds = getSaleIdsOfProject(_projectId);
        SaleInfo[] memory sales_ = new SaleInfo[](saleIds.length);
        for (uint256 i; i < saleIds.length; i++) {
            sales_[i] = sales[saleIds[i]];
        }
        return sales_;
    }

    /**
     * @notice Show all addresses buyers from sale ID
     * @param _saleId from sale ID
     */ 
    function getBuyers(uint256 _saleId) external view returns (address[] memory) {
        return buyers[_saleId];
    }

    /**
     * @notice Show sale info from sale ID
     * @param _saleId from sale ID
     */ 
    function getSaleById(uint256 _saleId) external view returns (SaleInfo memory) {
        return sales[_saleId];
    }

    /**
     * @notice Buy NFT from sale ID
     * @param _saleId from sale ID
     * @param _merkleProof merkle proof
     * @param _amount token amount
     */ 
    function buy(uint256 _saleId, bytes32[] memory _merkleProof, uint256 _amount) external payable nonReentrant saleIsValid(_saleId) {
        require(MerkleProofUpgradeable.verify(_merkleProof, merkleRoots[_saleId], keccak256(abi.encodePacked(_msgSender()))), "Invalid winner");
        SaleInfo storage sale = sales[_saleId];
        ProjectInfo memory _project = project.getProject(sale.projectId);

        uint256 _price = (_project.isFixed ? sale.fixedPrice : getCurrentDutchPrice(_saleId)) * _amount;
        require(_project.isSingle ? _amount == 1 : _amount > 0 && _amount <= sale.amount, "Invalid amount");
        require(_project.isFixed ? msg.value == _price : msg.value >= _price, "Invalid value");

        sale.amount -= _amount;
        sale.isSoldOut = sale.amount == 0;

        uint256 soldAmount = _project.sold + _amount;
        _project = project.getProject(sale.projectId);
        if (_project.isInstantPayment && soldAmount == _project.amount) project.end(_project.id);

        if (!bought[_saleId][_msgSender()]) {
            bought[_saleId][_msgSender()] = true;
            buyers[_saleId].push(_msgSender());
        }
     
        if (_project.isInstantPayment) {
            _project.isSingle ? IOSB721(_project.token).safeTransferFrom(address(this), _msgSender(), sale.tokenId) :
            IOSB1155(_project.token).safeTransferFrom(address(this), _msgSender(), sale.tokenId, _amount, "");
            sale.isClose = sale.isSoldOut;
            if (sale.isClose) project.setTotalSalesNotClose(_project.id, project.getTotalSalesNotClose(_project.id) - 1);
        } 

        project.setSoldQuantityToProject(sale.projectId, soldAmount);
        _sharing(_project, sale, _amount, _price);
    }

    /**
     * @notice Support sharing profit or log bill
     * @param _project project info
     * @param _sale sale info
     * @param _amount token amount
     * @param _price payment price
     */ 
    function _sharing(ProjectInfo memory _project, SaleInfo memory _sale, uint256 _amount, uint256 _price) private {
        uint256 supperAdminProfit; 
        uint256 royaltyProfit;
        uint256 sellerProfit;
        uint256 residualPrice;

        if (msg.value > _price) residualPrice = msg.value - _price;
        
        // Calculate royal fee
        (address royaltyReceiver, uint256 royaltyFee) = getRoyaltyInfo(_project.id, _sale.tokenId, _price);
        royaltyProfit = royaltyFee;

        // Calculate fee and profit
        if (_project.isCreatedByAdmin) {
            supperAdminProfit = _price - royaltyProfit;
        } else {
            // admin fee
            supperAdminProfit = _getPriceToPercent(_price, _project.profitShare);
            sellerProfit = _price - supperAdminProfit;
            if (royaltyProfit > sellerProfit) royaltyProfit = sellerProfit;
            sellerProfit -= royaltyProfit;
        }

        supperAdminProfit += residualPrice;

        // Transfer fee and profit
        if (_project.minSales == 0 && _project.isInstantPayment) {
            if (royaltyProfit > 0) Helper.safeTransferNative(royaltyReceiver, royaltyProfit);
            if (supperAdminProfit > 0) Helper.safeTransferNative(setting.getSuperAdmin(), supperAdminProfit);
            if (sellerProfit > 0) Helper.safeTransferNative(project.getManager(_project.id), sellerProfit);
        } else {
            Bill storage billInfo = bills[_sale.id][_msgSender()];
            if (billInfo.account != _msgSender()) {
                project.setTotalBuyersWaitingDistribution(_project.id, project.getTotalBuyersWaitingDistribution(_project.id) + 1);
                buyersWaitingDistributions[_sale.id].push(_msgSender());
            }
            billInfo.saleId = _sale.id;
            billInfo.account = _msgSender();
            billInfo.amount += _amount;
            billInfo.royaltyReceiver = royaltyReceiver;
            billInfo.royaltyFee += royaltyProfit;
            billInfo.superAdminFee += supperAdminProfit;
            billInfo.sellerFee += sellerProfit;
        }
        
        emit Buy(_msgSender(), _sale.id, _sale.tokenId, _amount, _project.profitShare, supperAdminProfit, royaltyProfit, sellerProfit, residualPrice);
    }

    /// @notice Support calculate price to percent
    function _getPriceToPercent(uint256 _price, uint256 _percent) private pure returns (uint256) {
        return (_price * _percent) / (100 * WEIGHT_DECIMAL);
    }
}

