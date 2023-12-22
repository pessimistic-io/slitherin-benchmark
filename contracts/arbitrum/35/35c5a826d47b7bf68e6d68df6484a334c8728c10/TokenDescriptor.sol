// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;
import "./Strings.sol";
import "./IERC20Metadata.sol";
import "./Base64.sol";
import "./IUniswapV3Pool.sol";
import "./Create2.sol";

import "./MetaProxyView.sol";
import "./IPool.sol";
import "./ITokenDescriptor.sol";
import "./IPoolFactory.sol";

contract TokenDescriptor is ITokenDescriptor {
    uint256 internal constant SIDE_A = 0x10;
    uint256 internal constant SIDE_B = 0x20;
    uint256 internal constant SIDE_C = 0x30;

    address internal immutable POOL_FACTORY;

    modifier onlyDerivableToken(uint256 id) {
        address pool = address(uint160(id));
        require(
            _computePoolAddress(IPool(pool).loadConfig()) == pool,
            "NOT_A_DERIVABLE_TOKEN"
        );
        _;
    }

    constructor(address poolFactory) {
        POOL_FACTORY = poolFactory;
    }

    function getName(
        uint256 id
    )
        public
        view
        virtual
        override
        onlyDerivableToken(id)
        returns (string memory)
    {
        address pool = address(uint160(id));
        bytes32 oracle = IPool(pool).loadConfig().ORACLE;
        (address base, address quote) = _getBaseQuote(oracle);
        uint256 side = id >> 160;
        return _getName(base, quote, pool, side);
    }

    function getSymbol(
        uint256 id
    )
        public
        view
        virtual
        override
        onlyDerivableToken(id)
        returns (string memory)
    {
        address pool = address(uint160(id));
        bytes32 oracle = IPool(pool).loadConfig().ORACLE;
        (address base, address quote) = _getBaseQuote(oracle);
        uint256 side = id >> 160;
        return _getSymbol(base, quote, pool, side);
    }

    function getDecimals(
        uint256 id
    ) public view virtual override onlyDerivableToken(id) returns (uint8) {
        address pool = address(uint160(id));
        return IERC20Metadata(IPool(pool).loadConfig().TOKEN_R).decimals();
    }

    function constructMetadata(
        uint256 id
    )
        public
        view
        virtual
        override
        onlyDerivableToken(id)
        returns (string memory)
    {
        address pool = address(uint160(id));
        bytes32 oracle = IPool(pool).loadConfig().ORACLE;
        (address base, address quote) = _getBaseQuote(oracle);
        uint256 side = id >> 160;
        string memory image = Base64.encode(bytes(_getImage()));
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                _getName(base, quote, pool, side),
                                '", "description":"',
                                _getDescription(base, quote, pool, side),
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function _getDescription(
        address base,
        address quote,
        address pool,
        uint256 side
    ) internal view returns (string memory) {
        Config memory config = IPool(pool).loadConfig();
        string memory sideStr;
        if (side == SIDE_C) {
            return
                string(
                    abi.encodePacked(
                        "This is a Derivable Liquidity Provider token for the ",
                        IERC20Metadata(base).symbol(),
                        "/",
                        IERC20Metadata(quote).symbol(),
                        " ",
                        "x",
                        _getPower(config.K),
                        " ",
                        "pool at ",
                        Strings.toHexString(uint160(pool), 20),
                        " ",
                        "with ",
                        IERC20Metadata(config.TOKEN_R).symbol(),
                        " as the reserve token."
                    )
                );
        } else {
            if (side == SIDE_A) {
                sideStr = "LONG";
            } else if (side == SIDE_B) {
                sideStr = "SHORT";
            }
            return
                string(
                    abi.encodePacked(
                        "This fungible token represents a Derivable ",
                        sideStr,
                        " x",
                        _getPower(config.K),
                        " ",
                        "position for the ",
                        IERC20Metadata(base).symbol(),
                        "/",
                        IERC20Metadata(quote).symbol(),
                        " ",
                        "pool at ",
                        Strings.toHexString(uint160(pool), 20),
                        " ",
                        "with ",
                        IERC20Metadata(config.TOKEN_R).symbol(),
                        " as the reserve token."
                    )
                );
        }
    }

    function _getName(
        address base,
        address quote,
        address pool,
        uint256 side
    ) internal view returns (string memory) {
        Config memory config = IPool(pool).loadConfig();
        string memory sideStr = "LP";
        if (side == SIDE_A) {
            sideStr = "Long";
        } else if (side == SIDE_B) {
            sideStr = "Short";
        }
        return
            string(
                abi.encodePacked(
                    sideStr,
                    " ",
                    _getPower(config.K),
                    "x",
                    " ",
                    IERC20Metadata(base).symbol(),
                    "/",
                    IERC20Metadata(quote).symbol(),
                    " ",
                    "(",
                    IERC20Metadata(config.TOKEN_R).symbol(),
                    ")"
                )
            );
    }

    function _getSymbol(
        address base,
        address quote,
        address pool,
        uint256 side
    ) internal view returns (string memory) {
        Config memory config = IPool(pool).loadConfig();
        string memory sideStr = "(LP)";
        if (side == SIDE_A) {
            sideStr = "+";
        } else if (side == SIDE_B) {
            sideStr = "-";
        }
        return
            string(
                abi.encodePacked(
                    IERC20Metadata(config.TOKEN_R).symbol(),
                    sideStr,
                    _getPower(config.K),
                    "x",
                    IERC20Metadata(base).symbol(),
                    "/",
                    IERC20Metadata(quote).symbol()
                )
            );
    }

    function _getBaseQuote(
        bytes32 oracle
    ) internal view returns (address base, address quote) {
        uint256 qti = (uint256(oracle) & (1 << 255) == 0) ? 0 : 1;
        address pair = address(uint160(uint256(oracle)));
        base = (qti == 0)
            ? IUniswapV3Pool(pair).token1()
            : IUniswapV3Pool(pair).token0();
        quote = (qti == 0)
            ? IUniswapV3Pool(pair).token0()
            : IUniswapV3Pool(pair).token1();
    }

    function _getPower(uint256 k) internal pure returns (string memory) {
        return
            (k % 2 == 0)
                ? Strings.toString(k / 2)
                : string(abi.encodePacked(Strings.toString(k / 2), ".5"));
    }

    /* solhint-disable */
    function _getImage() internal pure returns (string memory svg) {
        return
            string(
                abi.encodePacked(
                    '<svg width="148" height="137" viewBox="0 0 148 137" fill="none" xmlns="http://www.w3.org/2000/svg">',
                    '<path d="M80.0537 108.183V136.31H0V0H84.1578C114.181 0 147.129 23.5 147.129 69.2369H119.001C119.001 47.5 103.681 29.0301 84.1578 29.0301H28.7107V108.183H80.0537Z" fill="#01A7FA"/>',
                    '<mask id="path-2-inside-1_164_13183" fill="white">',
                    '<path fill-rule="evenodd" clip-rule="evenodd" d="M56.255 51.9277H88.7098V77.0548L105.473 90.8735H147.128V136.31H99.5281V99.3905L81.322 84.3825H56.255V51.9277Z"/>',
                    '</mask>',
                    '<path fill-rule="evenodd" clip-rule="evenodd" d="M56.255 51.9277H88.7098V77.0548L105.473 90.8735H147.128V136.31H99.5281V99.3905L81.322 84.3825H56.255V51.9277Z" fill="#F2F2F2"/>',
                    '<path d="M88.7098 51.9277H89.2098V51.4277H88.7098V51.9277ZM56.255 51.9277V51.4277H55.755V51.9277H56.255ZM88.7098 77.0548H88.2098V77.2906L88.3918 77.4406L88.7098 77.0548ZM105.473 90.8735L105.155 91.2593L105.294 91.3735H105.473V90.8735ZM147.128 90.8735H147.628V90.3735H147.128V90.8735ZM147.128 136.31V136.81H147.628V136.31H147.128ZM99.5281 136.31H99.0281V136.81H99.5281V136.31ZM99.5281 99.3905H100.028V99.1547L99.8461 99.0047L99.5281 99.3905ZM81.322 84.3825L81.64 83.9967L81.5015 83.8825H81.322V84.3825ZM56.255 84.3825H55.755V84.8825H56.255V84.3825ZM88.7098 51.4277H56.255V52.4277H88.7098V51.4277ZM89.2098 77.0548V51.9277H88.2098V77.0548H89.2098ZM88.3918 77.4406L105.155 91.2593L105.791 90.4877L89.0279 76.669L88.3918 77.4406ZM147.128 90.3735H105.473V91.3735H147.128V90.3735ZM147.628 136.31V90.8735H146.628V136.31H147.628ZM99.5281 136.81H147.128V135.81H99.5281V136.81ZM99.0281 99.3905V136.31H100.028V99.3905H99.0281ZM99.8461 99.0047L81.64 83.9967L81.0039 84.7684L99.21 99.7763L99.8461 99.0047ZM56.255 84.8825H81.322V83.8825H56.255V84.8825ZM55.755 51.9277V84.3825H56.755V51.9277H55.755Z" fill="#01A7FA" mask="url(#path-2-inside-1_164_13183)"/>',
                    '</svg>'
                )
            );
    }
    /* solhint-enable */

    function _computePoolAddress(
        Config memory config
    ) private view returns (address pool) {
        bytes memory input = abi.encode(config);
        bytes32 bytecodeHash = MetaProxyView.computeBytecodeHash(
            IPoolFactory(POOL_FACTORY).LOGIC(),
            input
        );
        return Create2.computeAddress(0, bytecodeHash, POOL_FACTORY);
    }
}

