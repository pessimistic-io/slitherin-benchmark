pragma solidity ^0.5.16;

import "./PriceOracle.sol";
import "./CErc20.sol";

contract MetaPriceOracle is PriceOracle {
    mapping(address => uint) prices;
    address public provider;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

	constructor() public {
		provider = msg.sender;
	}

    modifier onlyProvider() {
        require(provider == msg.sender, 'not provider: wut?');
        _;
    }
    function setProvider(address newProvider) public onlyProvider {
		provider = newProvider;
	}

    function _getUnderlyingAddress(CToken cToken) internal view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), "gETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
