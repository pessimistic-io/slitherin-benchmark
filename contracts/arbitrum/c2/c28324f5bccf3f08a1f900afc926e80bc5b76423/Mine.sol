// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./IMine.sol";
import "./ITreasury.sol";
import "./ITraits.sol";
import "./IRandom.sol";
import "./IWell.sol";
import "./ICapacityPackage.sol";
import "./IMinePool.sol";
import "./IWETH.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";

interface IDiscount {
    function getDiscountAndReduce(address _user) external returns (uint256);
}

interface IRebate {
    function isValidReferrer(address _referrer) external view returns(bool);
    function rebateTo(address _referrer, address _token, uint256 _amount) external returns(uint256);
}

contract Mine is IMine, OwnableUpgradeable, ERC721EnumerableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event UpdateTraits(sMine w);
    event Buy(address indexed account, uint8 payToken, sMine w, address referrer, uint256 bonus);
    event ConsumeCapacityPackage(address indexed account, uint32 tokenId, uint256 capacity);

    struct MineConfig {
        uint8 cid;
        uint8 nftType;
        uint32 minCapacityBuf;
        uint32 maxCapacityBuf;
        uint32 minSpeedBuf;
        uint32 maxSpeedBuf;
        uint256 price;
        string name;
        string des; 
    }

    struct Referrer {
        bool valid;
        address[2] referrers;
    }

    ITraits public traits;
    ITreasury public treasury;
    IRandom public random;
    ICapacityPackage public capacityPackage;
    IWell public well;
    IMinePool public minePool;
    mapping(uint32 => sMine) public tokenTraits;
    mapping(address => bool) public authControllers;
    mapping(uint8 => MineConfig) public configs;
    mapping(address => Referrer) public referrers;
    mapping(uint8 => uint32) public cidToMinted;
    uint8 public referBonus;

    uint32 public maxG0Amount;
    uint32 public maxSupply;
    uint32 public minted;
    bool public startG1Mint;
    IDiscount public discount;
    IRebate public rebate;
    uint32 public max_mint;

    function initialize(
        address _traits,
        address _treasury,
        address _random,
        address _capacityPackage,
        address _well,
        address _rebate
    ) external initializer {
        require(_traits != address(0));
        require(_treasury != address(0));
        require(_random != address(0));
        require(_capacityPackage != address(0));
        require(_well != address(0));
        require(_rebate != address(0));

        __ERC721_init("EnergyCrisis Mine", "ECM");
        __ERC721Enumerable_init();
        __Ownable_init();
        __Pausable_init();

        traits = ITraits(_traits);
        treasury = ITreasury(_treasury);
        random = IRandom(_random);
        capacityPackage = ICapacityPackage(_capacityPackage);
        well = IWell(_well);
        rebate = IRebate(_rebate);
        maxG0Amount = 2100;
        maxSupply = 21000;
        startG1Mint = false;
        referBonus = 10;
        max_mint = 10;
    }

    function setMaxG0Amount(uint32 _amount) external onlyOwner {
        maxG0Amount = _amount;
    }

    function setMaxSupply(uint32 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    function setConfigs(MineConfig[] memory _configs) external onlyOwner {
        for (uint256 i = 0; i < _configs.length; ++i) {
            MineConfig memory c = _configs[i];
            configs[c.cid] = c;
        }
    }

    function setReferBonus(uint8 _bonus) external onlyOwner {
        referBonus = _bonus;
    }

    function setMinePool(address _minePool) external onlyOwner {
        require(_minePool != address(0));
        minePool = IMinePool(_minePool);
    }

    function setStartG1Mint() external onlyOwner {
        require(minted >= maxG0Amount, "G0 mint not finished");
        require(startG1Mint == false, "G1 mint already started");
        startG1Mint = true;
    }

    function setDiscount(address _discount) external onlyOwner {
        require(_discount != address(0));
        discount = IDiscount(_discount);
    }

    function setRandom(address _random) external onlyOwner {
        require(_random != address(0));
        random = IRandom(_random);
    }

    function setMaxMint(uint32 _max_mint) external onlyOwner {
        max_mint = _max_mint;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    receive() external payable {}

    //_payToken: 0 USDT or WETH, 1 Oil
    function buy(uint8 _payToken, uint8 _cid, address _referrer) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        require(_msgSender() != _referrer, "Referrer can't be self");
        require(minted < maxSupply, "Reached the max supply");
        if (minted < maxG0Amount) {
            _payToken = 0;
        } else {
            require(startG1Mint == true, "G1 mint not started");
        }

        if (max_mint > 0) {
            require(balanceOf(msg.sender) < max_mint, "Exceed max mint amount");
        }

        Referrer memory refferr1 = referrers[msg.sender];
        if (refferr1.referrers[0] != address(0)) {
            _referrer = refferr1.referrers[0];
        }
        MineConfig memory c = configs[_cid];
        require(_cid == c.cid, "Invalid params");
        (address token, uint256 amount) = treasury.getAmount(_payToken, c.price);
        uint256 off = (address(discount) == address(0)) ? 100 : discount.getDiscountAndReduce(_msgSender());
        if (off > 0) {
            amount = amount * off / 100;
            if (treasury.isNativeToken(token)) {
                require(amount == msg.value, "amount != msg.value");
                IWETH(token).deposit{value: msg.value}();
                if (_referrer != address(0)) {
                    _safeApprove(token, address(rebate));
                    amount = rebate.rebateTo(_referrer, token, amount);
                }
            } else {
                IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            }

            IERC20(token).safeTransfer(address(treasury), amount);
            treasury.buyBack(_payToken, amount);
        }

        sMine memory m;
        m.cid = c.cid;
        m.nftType = c.nftType;
        m.tokenId = minted + 1;
        if (minted < maxG0Amount) {
            m.gen = 0;
            m.capacity = c.price * 4;
            m.speedBuf = c.maxSpeedBuf;
            well.mint(msg.sender);
        } else {
            m.gen = 1;
            uint256[] memory r = random.multiRandomSeeds(minted, 2);
            if (c.maxCapacityBuf == c.minCapacityBuf) {
                m.capacity = c.price * c.maxCapacityBuf;
            } else {
                uint32 capacityBuf = c.minCapacityBuf + uint32(r[0] % (c.maxCapacityBuf - c.minCapacityBuf) + 1);
                m.capacity = c.price * capacityBuf;
            }

            if (c.maxSpeedBuf == c.minSpeedBuf) {
                m.speedBuf = c.maxSpeedBuf;
            } else {
                m.speedBuf = c.maxSpeedBuf + uint32(r[1] % (c.maxSpeedBuf - c.minSpeedBuf));
            }
        }

        uint256 bonus = 0;
        if (_referrer != address(0) && referBonus > 0) {
            if (refferr1.referrers[0] == address(0)) {
                Referrer memory refferr2 = referrers[_referrer];
                //require(refferr2.valid == true, "Invalid referrer");
                refferr1.referrers[0] = _referrer;
                refferr1.referrers[1] = refferr2.referrers[0];
            } else {
                if (refferr1.referrers[1] == address(0)) {
                    Referrer memory refferr2 = referrers[refferr1.referrers[0]];
                    refferr1.referrers[1] = refferr2.referrers[0];
                }
            }

            address[] memory r3 = new address[](3);
            uint256[] memory c3 = new uint256[](3);
            r3[0] = msg.sender;
            r3[1] = refferr1.referrers[0];
            r3[2] = refferr1.referrers[1];
            c3[0] = m.capacity * referBonus / 100;
            c3[1] = c3[0];
            c3[2] = c3[0];
            capacityPackage.addCapacity(r3, c3);
            bonus = c3[0];
        }
        tokenTraits[m.tokenId] = m;
        refferr1.valid = true;
        referrers[msg.sender] = refferr1;
        minted++;
        cidToMinted[_cid] += 1;
        _safeMint(msg.sender, m.tokenId);
        emit Buy(msg.sender, _payToken, m, _referrer, bonus);
    }

    function consumeCapacityPackage(uint32 _tokenId, uint256 _capacity) external whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        require(ownerOf(_tokenId) == msg.sender, "Not owner");
        require(_capacity > 0, "Invalid capacity");

        capacityPackage.subCapacity(msg.sender, _capacity);
        tokenTraits[_tokenId].capacity += _capacity;
        minePool.addCapacity(_tokenId, _capacity);
        emit ConsumeCapacityPackage(msg.sender, _tokenId, _capacity);
    }

    function updateTokenTraits(sMine memory _w) external override {
        require(authControllers[_msgSender()], "no auth");
        tokenTraits[_w.tokenId] = _w;
        emit UpdateTraits(_w);
    }

    function getTokenTraits(uint256 _tokenId) external view override returns (sMine memory) {
        return tokenTraits[uint32(_tokenId)];
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId));
        return traits.tokenURI(_tokenId);
    }

    function getReferrer(address _account) public view override returns(address[2] memory) {
        return referrers[_account].referrers;
    }

    function isValidReferrer(address _account) public view returns(bool) {
        return referrers[_account].valid || rebate.isValidReferrer(_account);
    }

    function mineInfo() public view returns(
        uint256 maxG0Amount_, 
        uint32 maxSupply_, 
        uint32 minted_, 
        bool startG1Mint_,
        uint32[3] memory eachTypeMinted_
    ) {
        maxG0Amount_ = maxG0Amount;
        maxSupply_ = maxSupply;
        minted_ = minted;
        startG1Mint_ = startG1Mint;
        eachTypeMinted_[0] = cidToMinted[1];
        eachTypeMinted_[1] = cidToMinted[2];
        eachTypeMinted_[2] = cidToMinted[3];
    }

    function eachTypeG0Capacity() public override view returns(uint256[3] memory capacity_) {
        for (uint8 i = 0; i < 3; ++i) {
            uint8 cid = i + 1;
            MineConfig memory c = configs[cid];
            capacity_[i] = cidToMinted[cid] * c.price * 4;
        } 
    }

    function _safeApprove(address _token, address _spender) internal {
        if (_token != address(0) && IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }
}


