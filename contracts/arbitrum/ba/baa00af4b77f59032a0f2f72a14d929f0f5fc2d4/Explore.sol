// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./ITreasury.sol";
import "./IRandom.sol";
import "./ICapacityPackage.sol";
import "./IMine.sol";
import "./IWETH.sol";
import "./IRebate.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";

interface IDiscount {
    function getDiscountAndReduce(address _user) external returns (uint256);
}

contract Explore is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct ExploreConfig {
        uint8 cid;
        uint8 minCapacityBuf;
        uint8 maxCapacityBuf;
        uint256 price;
    }
    
    event ExploreResult(address indexed account, uint8 payToken, uint8 cid, uint256 capacity, uint256 bonus);

    IMine public mine;
    ITreasury public treasury;
    IRandom public random;
    ICapacityPackage public capacityPackage;
    mapping(uint8 => ExploreConfig) public configs;
    uint8 public referBonus;
    mapping(uint8 => uint32) public cidToMinted;
    uint32 public minted;
    IDiscount public discount;
    IRebate public rebate;

    function initialize(
        address _mine,
        address _treasury,
        address _random,
        address _capacityPackage
    ) external initializer {
        require(_mine != address(0));
        require(_treasury != address(0));
        require(_random != address(0));
        require(_capacityPackage != address(0));

        __Ownable_init();
        __Pausable_init();

        mine = IMine(_mine);
        treasury = ITreasury(_treasury);
        random = IRandom(_random);
        capacityPackage = ICapacityPackage(_capacityPackage);
        referBonus = 5;
    }

    function setConfigs(ExploreConfig[] memory _configs) external onlyOwner {
        for (uint256 i = 0; i < _configs.length; ++i) {
            ExploreConfig memory c = _configs[i];
            configs[c.cid] = c;
        }
    }

    function setReferBonus(uint8 _bonus) external onlyOwner {
        referBonus = _bonus;
    }

    function setDiscount(address _discount) external onlyOwner {
        require(_discount != address(0));
        discount = IDiscount(_discount);
    }

    function setRandom(address _random) external onlyOwner {
        require(_random != address(0));
        random = IRandom(_random);
    }

    function setRebate(address _rebate) external onlyOwner {
        require(_rebate != address(0));
        rebate = IRebate(_rebate);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    receive() external payable {}

    //_payToken: 0 USDT or WETH, 1 Oil
    function explore(uint8 _payToken, uint8 _cid) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        ExploreConfig memory c = configs[_cid];
        require(_cid == c.cid, "Invalid params");
        address[2] memory referrers = mine.getReferrer(msg.sender);
        (address token, uint256 amount) = treasury.getAmount(_payToken, c.price);
        uint256 off = (address(discount) == address(0)) ? 100 : discount.getDiscountAndReduce(_msgSender());
        if (off > 0) {
            amount = amount * off / 100;
            if (treasury.isNativeToken(token)) {
                require(amount == msg.value, "amount != msg.value");
                IWETH(token).deposit{value: msg.value}();
                if (referrers[0] != address(0)) {
                    _safeApprove(token, address(rebate));
                    amount = rebate.rebateTo(referrers[0], token, amount);
                }
                IERC20(token).safeTransfer(address(treasury), amount);
            } else {
                IERC20(token).safeTransferFrom(msg.sender, address(treasury), amount);
            }
            treasury.buyBack(_payToken, amount);
        }
        
        uint256 capacity = 0;
        if (c.maxCapacityBuf == c.minCapacityBuf) {
            capacity = c.price * c.maxCapacityBuf;
        } else {
            uint256 r = random.randomseed(minted);
            uint8 capacityBuf = c.minCapacityBuf + uint8(r % (c.maxCapacityBuf - c.minCapacityBuf) + 1);
            capacity = c.price * capacityBuf;
        }

        address[] memory r3 = new address[](3);
        uint256[] memory c3 = new uint256[](3);
        r3[0] = msg.sender;
        r3[1] = referrers[0];
        r3[2] = referrers[1];
        uint256 bonus = (referrers[0] != address(0)) ? capacity * referBonus / 100 : 0;
        c3[0] = capacity + bonus;
        c3[1] = bonus;
        c3[2] = bonus;
        capacityPackage.addCapacity(r3, c3);
        minted++;
        cidToMinted[_cid] += 1;
        emit ExploreResult(msg.sender, _payToken, _cid, capacity, bonus);
    }

    function _safeApprove(address _token, address _spender) internal {
        if (_token != address(0) && IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint256).max);
        }
    }
}
