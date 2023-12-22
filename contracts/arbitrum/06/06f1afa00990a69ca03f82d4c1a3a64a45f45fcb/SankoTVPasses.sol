// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "./Ownable.sol";
import {IFeeConverter} from "./IFeeConverter.sol";

error StreamerMustBuyFirstPass();
error CannotSellLastPass();
error InsufficientPayment();
error InsufficientPasses();
error FundsTransferFailed();
error NotLiveYet();
error NotUnlockedYet();
error UnlocksTooSoon();

contract SankoTVPasses is Ownable {
    struct PackedArgs {
        uint96 amount;
        address addy;
    }

    struct Fees {
        uint256 streamerFee;
        uint256 ethFee;
        uint256 dmtFee;
        uint256 referralFee;
    }

    struct PassesBalance {
        uint96 unlocked;
        uint96 locked;
        uint64 unlocksAt;
    }

    address public protocolFeeDestination;
    IFeeConverter public feeConverter;
    uint256 public ethFeePercent;
    uint256 public dmtFeePercent;
    uint256 public streamerFeePercent;
    uint256 public referralFeePercent;

    bool public live;

    event Trade(
        address indexed trader,
        address indexed streamer,
        address indexed referrer,
        bool isBuy,
        uint256 passAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 streamerEthAmount,
        uint256 referralEthAmount,
        uint256 supply
    );

    event Locked(
        address indexed trader,
        address indexed streamer,
        uint256 passAmount,
        uint256 unlocksAt
    );

    event Unlocked(
        address indexed trader, address indexed streamer, uint256 passAmount
    );

    mapping(address streamer => mapping(address fan => PassesBalance balance))
        public passesBalance;

    mapping(address streamer => uint256 supply) public passesSupply;

    modifier whenLive() {
        if (!live) {
            revert NotLiveYet();
        }
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setLive() external onlyOwner {
        live = true;
    }

    function setFeeDestination(address _feeDestination) external onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setEthFeePercent(uint256 _feePercent) external onlyOwner {
        ethFeePercent = _feePercent;
    }

    function setDmtFeePercent(uint256 _feePercent) external onlyOwner {
        dmtFeePercent = _feePercent;
    }

    function setFeeConverter(IFeeConverter _feeConverter) external onlyOwner {
        feeConverter = _feeConverter;
    }

    function setStreamerFeePercent(uint256 _feePercent) external onlyOwner {
        streamerFeePercent = _feePercent;
    }

    function setReferralFeePercent(uint256 _feePercent) external onlyOwner {
        referralFeePercent = _feePercent;
    }

    function buyPasses(address streamer, bytes32 packedArgs)
        external
        payable
        whenLive
    {
        PackedArgs memory args = unpackArgs(packedArgs);
        uint96 amount = args.amount;
        address referrer = args.addy;

        uint256 supply = passesSupply[streamer];
        if (supply == 0 && msg.sender != streamer) {
            revert StreamerMustBuyFirstPass();
        }

        uint256 price = getPrice(supply, amount);
        Fees memory fees = getFees(price, referrer);

        uint256 totalCost = price + fees.ethFee + fees.dmtFee + fees.streamerFee
            + fees.referralFee;

        if (msg.value < totalCost) {
            revert InsufficientPayment();
        }

        passesBalance[streamer][msg.sender].unlocked += amount;
        passesSupply[streamer] = supply + amount;
        emit Trade(
            msg.sender,
            streamer,
            referrer,
            true,
            amount,
            price,
            fees.ethFee + fees.dmtFee,
            fees.streamerFee,
            fees.referralFee,
            supply + amount
        );

        (bool streamerSend,) = streamer.call{value: fees.streamerFee}("");
        (bool protocolSend,) =
            protocolFeeDestination.call{value: fees.ethFee}("");

        bool feeSend = true;
        if (fees.dmtFee > 0) {
            feeSend = feeConverter.convertFees{value: fees.dmtFee}();
        }

        bool referrerSend = true;
        if (referrer != address(0)) {
            (referrerSend,) = referrer.call{value: fees.referralFee}("");
        }

        if (!(streamerSend && protocolSend && feeSend && referrerSend)) {
            revert FundsTransferFailed();
        }
    }

    function sellPasses(address streamer, bytes32 packedArgs)
        external
        payable
        whenLive
    {
        PackedArgs memory args = unpackArgs(packedArgs);
        uint96 amount = args.amount;
        address referrer = args.addy;

        uint256 supply = passesSupply[streamer];
        PassesBalance storage sellerBalance =
            passesBalance[streamer][msg.sender];

        if (sellerBalance.unlocked < amount) {
            revert InsufficientPasses();
        }
        if (supply <= amount) {
            revert CannotSellLastPass();
        }

        uint256 price = getPrice(supply - amount, amount);
        Fees memory fees = getFees(price, referrer);

        sellerBalance.unlocked -= amount;
        passesSupply[streamer] = supply - amount;
        emit Trade(
            msg.sender,
            streamer,
            referrer,
            false,
            amount,
            price,
            fees.ethFee + fees.dmtFee,
            fees.streamerFee,
            fees.referralFee,
            supply - amount
        );

        (bool sellerSend,) = msg.sender.call{
            value: price
                - (fees.ethFee + fees.dmtFee + fees.streamerFee + fees.referralFee)
        }("");

        (bool streamerSend,) = streamer.call{value: fees.streamerFee}("");
        (bool protocolSend,) =
            protocolFeeDestination.call{value: fees.ethFee}("");

        bool feeSend = true;
        if (fees.dmtFee > 0) {
            feeSend = feeConverter.convertFees{value: fees.dmtFee}();
        }

        bool referrerSend = true;
        if (referrer != address(0)) {
            (referrerSend,) = referrer.call{value: fees.referralFee}("");
        }

        if (
            !(
                sellerSend && streamerSend && protocolSend && feeSend
                    && referrerSend
            )
        ) {
            revert FundsTransferFailed();
        }
    }

    function lockPasses(bytes32 packedArgs, uint256 lockTimeSeconds)
        external
        whenLive
    {
        PackedArgs memory args = unpackArgs(packedArgs);
        uint96 amount = args.amount;
        address streamer = args.addy;

        PassesBalance memory balance = passesBalance[streamer][msg.sender];
        if (balance.unlocked < amount) {
            revert InsufficientPasses();
        }

        uint64 newUnlocksAt = uint64(block.timestamp + lockTimeSeconds);
        uint64 oldUnlocksAt = balance.unlocksAt;
        if (newUnlocksAt < oldUnlocksAt) {
            revert UnlocksTooSoon();
        }

        passesBalance[streamer][msg.sender] = PassesBalance({
            locked: balance.locked += amount,
            unlocked: balance.unlocked -= amount,
            unlocksAt: newUnlocksAt
        });

        emit Locked(msg.sender, streamer, amount, newUnlocksAt);
    }

    function unlockPasses(address streamer) external whenLive {
        PassesBalance memory balance = passesBalance[streamer][msg.sender];
        if (balance.unlocksAt > block.timestamp) {
            revert NotUnlockedYet();
        }

        if (balance.locked == 0) {
            revert InsufficientPasses();
        }

        passesBalance[streamer][msg.sender] = PassesBalance({
            locked: 0,
            unlocked: balance.unlocked + balance.locked,
            unlocksAt: 0
        });

        emit Unlocked(msg.sender, streamer, balance.locked);
    }

    function getPrice(uint256 supply, uint256 amount)
        public
        pure
        returns (uint256)
    {
        uint256 x1 = priceCurve(supply);
        uint256 x2 = priceCurve(supply + amount);

        return (x2 - x1) * 1 ether / 16_000;
    }

    function priceCurve(uint256 x) public pure returns (uint256) {
        if (x == 0) {
            return 0;
        }

        return (x - 1) * x * (2 * (x - 1) + 1) / 6;
    }

    function getFees(uint256 price, address referrer)
        public
        view
        returns (Fees memory)
    {
        uint256 ethFee;
        uint256 dmtFee;
        uint256 referralFee;
        if (referrer != address(0)) {
            referralFee = price * referralFeePercent / 1 ether;
            ethFee = price * ethFeePercent / 1 ether;
            dmtFee = price * dmtFeePercent / 1 ether;
        } else {
            referralFee = 0;
            uint256 referralFeePercentShare =
                dmtFeePercent > 0 ? referralFeePercent / 2 : referralFeePercent;
            ethFee = price * (ethFeePercent + referralFeePercentShare) / 1 ether;
            dmtFee = dmtFeePercent > 0
                ? price * (dmtFeePercent + referralFeePercentShare) / 1 ether
                : 0;
        }
        uint256 streamerFee = price * streamerFeePercent / 1 ether;
        return Fees({
            streamerFee: streamerFee,
            ethFee: ethFee,
            dmtFee: dmtFee,
            referralFee: referralFee
        });
    }

    function getBuyPrice(address streamer, uint256 amount)
        public
        view
        returns (uint256)
    {
        return getPrice(passesSupply[streamer], amount);
    }

    function getSellPrice(address streamer, uint256 amount)
        public
        view
        returns (uint256)
    {
        return getPrice(passesSupply[streamer] - amount, amount);
    }

    function getBuyPriceAfterFee(address streamer, uint256 amount)
        external
        view
        returns (uint256)
    {
        uint256 price = getBuyPrice(streamer, amount);
        Fees memory fees = getFees(price, address(0));
        return price + fees.ethFee + fees.dmtFee + fees.streamerFee
            + fees.referralFee;
    }

    function getSellPriceAfterFee(address streamer, uint256 amount)
        external
        view
        returns (uint256)
    {
        uint256 price = getSellPrice(streamer, amount);
        Fees memory fees = getFees(price, address(0));
        return price - fees.ethFee + fees.dmtFee + fees.streamerFee
            + fees.referralFee;
    }

    function unpackArgs(bytes32 args)
        private
        pure
        returns (PackedArgs memory)
    {
        // Extract the amount (first 12 bytes)
        uint96 amount = uint96(uint256(args) >> (160));

        // Extract the referrer or streamer address (last 20 bytes)
        address addy = address(uint160(uint256(args)));

        return PackedArgs({amount: amount, addy: addy});
    }

    function packArgs(PackedArgs calldata args) public pure returns (bytes32) {
        return bytes32(
            (uint256(uint96(args.amount)) << 160) | uint256(uint160(args.addy))
        );
    }
}

