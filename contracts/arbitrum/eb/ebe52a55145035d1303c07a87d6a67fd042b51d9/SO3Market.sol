// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Vars.sol";
import "./IChef.sol";
import "./ERC20.sol";
import "./UUPSUpgradeableExp.sol";

struct Miner {
    address host;
    uint128 worth;
    uint128 giff;
    uint256 vol;
}

contract SO3Market is UUPSUpgradeableExp {
    // --------------- event -----------
    event Mint(address miner, address host, uint256 value);
    event Grab(address indexed miner, address host, uint256 value, uint256 feeToTreasury, uint256 feeToMiner);
    event Like(address indexed miner, address user, uint256 giff);
    event Discount(address indexed miner, uint256 worth);
    event TreasuryChanged(address newTreasury);
    event FeePointChanged(uint256 toTreasury, uint256 toMiner);
    event MinerWhitelistChanged(address[] miners, bool enabled);
    // --------------- event end -----------

    // --------------- state -----------
    mapping(address => Miner) public miners;
    address public treasury;
    uint256 public tradeFeeToTreasuryBP;
    uint256 public tradeFeeToMinerBP;

    IChef public so3Chef;
    ERC20 public so3Token;

    mapping(address => bool) public minerWhitelist;
    bool public minerWhitelistEnabled;
    uint256 public tradeStartBlock;

    // --------------- state end-----------

    function initialize(address treasury_, ERC20 so3, IChef chef) external initializer {
        require(address(so3) != address(0), "EMPTY");
        require(address(chef) != address(0), "EMPTY");
        require(treasury_ != address(0), "EMPTY");
        so3Token = so3;
        so3Chef = chef;

        tradeFeeToTreasuryBP = 200; //2%
        tradeFeeToMinerBP = 100; //1%
        treasury = treasury_;
        minerWhitelistEnabled = true;
        _init();
    }

    // --------------- public function -----------
    function buy(address miner) external payable onlyTradeStarted {
        if (miner == msg.sender) revert DISABLE_BUY_SELF();
        if (minerWhitelistEnabled && !minerWhitelist[miner]) revert MINSER_IS_NOT_IN_LIST();

        if (miners[miner].host == address(0)) {
            //first active
            _mint(miner);
        } else {
            _grab(miner);
        }
    }

    function _mint(address miner) private {
        if (msg.value != MINT_PRICE) revert INVALID_MINT_PRICE();
        if (miner.code.length > 0) revert MINNER_MUSTBE_EOA();

        miners[miner] =
            Miner({host: msg.sender, worth: _safeCastTo128(getNextWorth(MINT_PRICE)), giff: 0, vol: MINT_PRICE});

        so3Chef.deposit(miner, msg.sender, getPower(MINT_PRICE, 0));

        require(_transferETH(treasury, MINT_PRICE), "F");

        emit Mint(miner, msg.sender, MINT_PRICE);
    }

    function _grab(address miner) private {
        Miner memory m = miners[miner];

        if (m.worth != msg.value) revert INVALID_BUY_PRICE();
        if (m.host == msg.sender) revert INVALID_BUYER();

        // transfer host & deposit
        so3Chef.setHost(miner, msg.sender);
        so3Chef.deposit(miner, msg.sender, getPower(msg.value, 0));

        //update pow and worth
        miners[miner].host = msg.sender;
        miners[miner].worth = _safeCastTo128(getNextWorth(m.worth));

        unchecked {
            miners[miner].vol = m.vol + msg.value;

            uint256 f1 = (msg.value * tradeFeeToTreasuryBP) / BP;
            uint256 f2 = (msg.value * tradeFeeToMinerBP) / BP;

            //skip failed transfer

            if (!_transferETH(miner, f2)) {
                f1 = f1 + f2;
                f2 = 0;
            }
            if (!_transferETH(m.host, msg.value - f1 - f2)) {
                f1 = msg.value - f2;
            }

            require(_transferETH(treasury, f1), "F");

            emit Grab(miner, msg.sender, msg.value, f1, f2);
        }
    }

    function like(address miner, uint256 giff, bytes calldata so3PermitCallData) external onlyTradeStarted {
        // permit check
        if (so3PermitCallData.length > 0) {
            Address.functionCall(address(so3Token), bytes.concat(ERC20.permit.selector, so3PermitCallData));
        }

        //burn so3
        uint256 amount = giff * 1000 * 1e18;
        require(so3Token.transferFrom(msg.sender, address(0), amount));

        Miner memory m = miners[miner];
        if (m.host == address(0)) revert MINNER_NOT_EXIST();
        miners[miner].giff = _safeCastTo128(m.giff + giff);
        so3Chef.deposit(miner, m.host, getPower(0, giff));

        emit Like(miner, msg.sender, giff);
    }

    function discount(address miner, uint256 worth) external onlyTradeStarted {
        Miner memory m = miners[miner];

        if (m.host == address(0)) revert MINNER_NOT_EXIST();
        if (m.host != msg.sender) revert UNAUTHORIZED();

        if (worth == 0 || worth >= m.worth) revert INVALID_WORTH();
        miners[miner].worth = _safeCastTo128(worth);

        emit Discount(miner, worth);
    }

    function withrawETH() public {
        require(_transferETH(treasury, address(this).balance), "F");
    }

    function getNextWorth(uint256 lastWorth) public pure returns (uint256) {
        // safe
        return lastWorth + (lastWorth * WORTH_INCREASE_BP) / BP;
    }

    function getPower(uint256 vol, uint256 giff) public pure returns (uint256) {
        return giff + MINTER_POWER_0 + (vol * MINTER_POWER_INCREASE) / 1e18;
    }

    function minerInfo(address miner)
        public
        view
        returns (address host_, uint256 worth, uint256 giff, uint256 vol, uint256 power)
    {
        Miner memory m = miners[miner];
        host_ = m.host;
        worth = m.worth;
        giff = m.giff;
        vol = m.vol;
        power = getPower(vol, giff);
    }

    // --------------- public function end -----------

    // --------------- administrator function -----------

    function setTreasury(address addr) external onlyOwner {
        treasury = addr;
        emit TreasuryChanged(addr);
    }

    function setFeeBP(uint256 toTreasuryBP, uint256 toMinerBP) external onlyOwner {
        require(toTreasuryBP + toMinerBP < BP);
        tradeFeeToTreasuryBP = toTreasuryBP;
        tradeFeeToMinerBP = toMinerBP;

        emit FeePointChanged(toTreasuryBP, toMinerBP);
    }

    function setChef(IChef chef) external onlyOwner {
        require(address(chef) != address(0));
        so3Chef = chef;
    }

    function setWhitelistStatus(bool enable) external onlyOwner {
        minerWhitelistEnabled = enable;
    }

    function setWhitelist(address[] calldata list, bool allow) external onlyOwner {
        for (uint256 i = 0; i < list.length; i++) {
            minerWhitelist[list[i]] = allow;
        }
        emit MinerWhitelistChanged(list, allow);
    }

    function setTradeStartBlock(uint256 blockNumber) external onlyOwner {
        tradeStartBlock = blockNumber;
    }

    // --------------- administrator function end -----------

    // --------------- private function -----------

    function _safeCastTo128(uint256 x) internal pure returns (uint128 y) {
        if (x >= 1 << 128) revert CAST_TO_128_OVERFLOW();
        y = uint128(x);
    }

    function _transferETH(address to, uint256 amount) internal returns (bool success) {
        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
    }

    modifier onlyTradeStarted() {
        if (tradeStartBlock > block.number) revert TRADE_NOT_STARTED();
        _;
    }

    // --------------- private function end -----------
}

