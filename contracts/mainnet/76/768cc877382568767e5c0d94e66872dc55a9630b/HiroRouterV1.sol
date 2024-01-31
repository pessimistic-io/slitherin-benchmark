//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./TransferHelper.sol";
import "./IERC20.sol";
import "./AggregatorV3Interface.sol";

contract HiroRouterV1 {
    address feeTreasury;

    // Example for 0.25% baseFee:
    //     baseFeeDivisor = 1 / 0.0025
    //     => 400
    uint256 public baseFeeDivisor; // fee = amount / baseFeeDivisor

    string public version;

    constructor(
        address _feeTreasury,
        uint256 _baseFeeDivisor,
        string memory _version
    ) {
        baseFeeDivisor = _baseFeeDivisor;
        feeTreasury = _feeTreasury;
        version = _version;
    }

    event Payment(
        address indexed sender,
        address indexed receiver,
        address token, /* the token that payee receives, use address(0) for AVAX*/
        uint256 amount,
        uint256 fees,
        bytes32 memo
    );

    event Convert(address indexed priceFeed, int256 exchangeRate);

    /*
    Basic payment router when sending tokens directly without DEX. 
    Most gas efficient. 

    Additional support for converting tokens via priceFeeds.

    ## Example: Pay without pricefeeds, e.g. USDC transfer

    payWithToken(
      "tx-123",   // memo
      5*10**18,   // 5$
      [],         // no pricefeeds
      0xUSDC,     // usdc token address
      0xAlice     // receiver token address
    )

    ## Example: Pay with pricefeeds (EUR / USD)

    The user entered the amount in EUR, which gets converted into
    USD by the on-chain pricefeed.

    payWithToken(
        "tx-123",   // memo
        4.5*10**18, // 4.5 EUR (~5$). 
        [0xEURUSD], // 
        0xUSDC,     // usdc token address
        0xAlice     // receiver token address
    )  


    ## Example: Pay with extra fee

    3rd parties can receive an extra fee that is taken directly from
    the receivable amount. 
    
    payWithToken(
        "tx-123",   // memo
        4.5*10**18, // 4.5 EUR (~5$). 
        [0xEURUSD], // 
        0xUSDC,     // usdc token address
        0xAlice,    // receiver token address
        0x3rdParty  // extra fee for 3rd party provider
        200,        // extra fee divisor (x = 1 / 0.005) => 0.5%
    )
    */
    function payWithToken(
        bytes32 _memo,
        uint256 _amount,
        address[] calldata _priceFeeds,
        address _token,
        address _receiver,
        address _extraFeeReceiver,
        uint256 _extraFeeDivisor
    ) external returns (bool) {
        require(_amount != 0, "invalid amount");

        // transform amount with _priceFeeds
        if (_priceFeeds.length > 0) {
            {
                int256 price;
                address priceFeed;
                (_amount, priceFeed, price) = exchangeRate(
                    _priceFeeds,
                    _amount
                );
                emit Convert(priceFeed, price);
            }
        }

        ensureAllowance(_token, _amount);

        uint256 totalFee = 0;

        if (_memo != "") {
            totalFee += transferFee(
                _amount,
                baseFeeDivisor,
                _token,
                msg.sender,
                feeTreasury
            );
        }

        if (_extraFeeReceiver != address(0)) {
            require(_extraFeeDivisor > 2, "extraFee too high");

            totalFee += transferFee(
                _amount,
                _extraFeeDivisor,
                _token,
                msg.sender,
                _extraFeeReceiver
            );
        }

        // Transfer to receiver
        TransferHelper.safeTransferFrom(
            _token,
            msg.sender,
            _receiver,
            _amount - totalFee
        );

        emit Payment(msg.sender, _receiver, _token, _amount, totalFee, _memo);

        return true;
    }

    /*
    Make life easier for frontends.
    */
    function ensureAllowance(address _token, uint256 _amount) private view {
        require(
            IERC20(_token).allowance(msg.sender, address(this)) >= _amount,
            "insufficient allowance"
        );
    }

    function transferFee(
        uint256 _amount,
        uint256 _feeDivisor,
        address _token,
        address _from,
        address _to
    ) private returns (uint256) {
        uint256 fee = _amount / _feeDivisor;
        // Transfer hiro-fee to treasury
        if (fee > 0) {
            TransferHelper.safeTransferFrom(_token, _from, _to, fee);
            return fee;
        } else {
            return 0;
        }
    }

    function exchangeRate(address[] calldata _priceFeeds, uint256 _amount)
        public
        view
        returns (
            uint256 converted,
            address priceFeed,
            int256 price
        )
    {
        require(_priceFeeds.length < 2, "invalid pricefeeds");

        // TODO: base / quote pricefeed to calc EUR/ETH via EUR/USD ETH/USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeeds[0]);

        uint256 decimals = uint256(10**uint256(priceFeed.decimals()));
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 converted = (_amount * uint256(price)) / decimals;

        return (converted, _priceFeeds[0], price);
    }
}

