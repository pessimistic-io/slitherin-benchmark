// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.4;
import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./KeeperCompatible.sol";
import "./ChainlinkClientUpgradable.sol";
import "./ComPool.sol";
import "./ERC721Token.sol";

contract ELPToken is ERC20Upgradeable, OwnableUpgradeable, KeeperCompatibleInterface, ChainlinkClientUpgradable {
    using Chainlink for Chainlink.Request;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public efunToken;
    address public poolAddress;
    uint256 public maxSellAmount;
    uint256 public maxSellAmountPerAddress;
    address payable public feeCollector;
    uint256 public counter;
    uint256 public lastTimeStamp;
    mapping(uint256 => mapping(address => uint256)) public totalSellAmount;
    uint256 public sellFee;
    address public erc721Token;
    address public elpAmtOfNft;
    mapping(uint256 => uint256) public classes;
    uint256[] public elpAmtOfClass;
    uint256 public oneHundredPrecent;
    uint256 public capacity;
    uint256[] public limits;
    uint256[] public counts;

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _poolAddress,
        address _efunToken,
        address _to,
        address payable _feeCollector,
        uint256 _elpAmt,
        uint256 _oneHundredPrecent,
        address _erc721Token
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);
        ChainlinkClientUpgradable.__ChainlinkClient_init();
        poolAddress = _poolAddress;
        efunToken = _efunToken;
        feeCollector = _feeCollector;
        oneHundredPrecent = _oneHundredPrecent;
        sellFee = (_oneHundredPrecent * 2) / 100;
        erc721Token = _erc721Token;
        elpAmtOfClass = [100 ether, 500 ether, 1000 ether, 5000 ether, 10000 ether];
        limits = [200, 30, 15, 4, 3];
        counts = [0, 0, 0, 0, 0];
        capacity = _elpAmt;
        _mint(_to, _elpAmt);
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
        feeCollector = payable(_feeCollector);
    }

    function currentNav() public view returns (uint256) {
        return ComPool(poolAddress).capacity() / capacity;
    }

    function setSellFee(uint256 _sellFee) public onlyOwner {
        sellFee = _sellFee;
    }

    function setErc721Token(address _erc721Token) public onlyOwner {
        erc721Token = _erc721Token;
    }

    function setElpAmtOfClass(uint256[] memory _elpAmtOfClass) public onlyOwner {
        elpAmtOfClass = _elpAmtOfClass;
    }

    function setLimits(uint256[] memory _limits) public onlyOwner {
        limits = _limits;
    }

    function setCounts(uint256[] memory _counts) public onlyOwner {
        counts = _counts;
    }

    function buyToken(uint256 _elpAmt) public {
        uint256[] memory x;
        _buyToken(_elpAmt, x, 0);
    }

    function sellToken(uint256 _elpAmt) public {
        uint256[] memory x;
        _sellToken(_elpAmt, x);
    }

    function buyNFT(uint256 _class, uint256 _quantity) public returns (uint256[] memory) {
        require(counts[_class] + _quantity <= limits[_class], "exceed-limits");
        uint256 elpAmt = elpAmtOfClass[_class];
        uint256 tokenId = ERC721Token(erc721Token).mint(msg.sender, _quantity, _class);
        uint256[] memory tokenIds = new uint256[](_quantity);
        for (uint256 i = 0; i < _quantity; ++i) {
            tokenIds[i] = tokenId + i;
            classes[tokenId + i] = _class;
            ++counts[_class];
        }
        _buyToken(elpAmt * _quantity, tokenIds, counts[_class]);
        return tokenIds;
    }

    function sellNft(uint256[] memory _tokenIds) public {
        ERC721Token(erc721Token).burn(_tokenIds, msg.sender);
        uint256 _elpAmt = 0;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            _elpAmt += elpAmtOfClass[classes[_tokenIds[i]]];
        }
        _sellToken(_elpAmt, _tokenIds);
    }

    function _buyToken(
        uint256 _elpAmt,
        uint256[] memory _nfts,
        uint256 _classId
    ) private {
        uint256 _currentNav = currentNav();
        uint256 _efunAmt = _currentNav * _elpAmt;
        IERC20Upgradeable(efunToken).safeTransferFrom(msg.sender, address(poolAddress), _efunAmt);
        emit TokenAction(msg.sender, _currentNav, _elpAmt, 0, _nfts, true, _classId, block.timestamp);
        capacity += _elpAmt;
        if (_nfts.length == 0) {
            _mint(msg.sender, _elpAmt);
        }
    }

    function _sellToken(uint256 _elpAmt, uint256[] memory _nfts) private {
        require(_elpAmt <= maxSellAmount, "exceed-total-sell-amount");
        require(totalSellAmount[counter][msg.sender] + _elpAmt <= maxSellAmountPerAddress, "exceed-amount-per-user");
        maxSellAmount -= _elpAmt;
        totalSellAmount[counter][msg.sender] += _elpAmt;
        uint256 _currentNav = currentNav();
        uint256 _efunAmt = _currentNav * _elpAmt;
        IERC20Upgradeable(efunToken).safeTransferFrom(
            address(poolAddress),
            msg.sender,
            (_efunAmt * (oneHundredPrecent - sellFee)) / oneHundredPrecent
        );
        IERC20Upgradeable(efunToken).safeTransferFrom(
            address(poolAddress),
            feeCollector,
            (_efunAmt * sellFee) / oneHundredPrecent
        );
        emit TokenAction(msg.sender, _currentNav, _elpAmt, sellFee, _nfts, false, 0, block.timestamp);
        capacity -= _elpAmt;
        if (_nfts.length == 0) {
            _burn(msg.sender, _elpAmt);
        }
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) >= 86390;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) public override {
        if ((block.timestamp - lastTimeStamp) >= 86390) {
            maxSellAmount = totalSupply() / 20;
            maxSellAmountPerAddress = maxSellAmount / 5;
            ++counter;
            lastTimeStamp = block.timestamp;
        }
    }

    /* =============== EVENTS ==================== */

    event TokenAction(
        address user,
        uint256 nav,
        uint256 amount,
        uint256 fee,
        uint256[] nftIds,
        bool isBuy,
        uint256 classId,
        uint256 timestamp
    );
}

