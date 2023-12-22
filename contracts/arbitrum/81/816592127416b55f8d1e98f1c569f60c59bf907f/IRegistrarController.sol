pragma solidity >=0.8.4;
import "./ISidPriceOracle.sol";
import "./SidStruct.sol";
interface IRegistrarController {
    
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);

    event NewPriceOracle(address indexed oracle);

    event NewTreasuryManager(address indexed treasuryManager);
    
    function rentPrice(string calldata name, uint256 duration) external view returns (ISidPriceOracle.Price memory);

    /**
     * rent price with point redemption
     * @param name domain name
     * @param duration registration duration
     * @param registerAddress address of the registrant
     */
    function rentPriceWithPoint(string calldata name, uint256 duration, address registerAddress) external view returns (ISidPriceOracle.Price memory);

    /**
     * bulk rent price without point redemption
     * @param names domain names
     * @param duration registration duration
     */
    function bulkRentPrice(string[] calldata names, uint256 duration) external view returns (uint256);

    function valid(string calldata name) external pure returns (bool);

    function available(string calldata name) external view returns (bool);

    function register(string calldata name, address owner, uint duration) external payable;
    
    function registerWithConfigAndPoint(string calldata name, address owner, uint duration, address resolver, bool isUsePoints, bool isSetPrimaryName, ReferralInfo memory referralInfo) external payable;

    function bulkRegister(string[] calldata names, address owner, uint duration, address resolver, bool isUsePoints, bool isSetPrimaryName, ReferralInfo memory referralInfo) external payable;

    function bulkRenew(string[] calldata names, uint duration, bool isUsePoints) external payable;
    
    function renew(string calldata name, uint duration) external payable;

    function renewWithPoint(string calldata name, uint duration, bool isUsePoints) external payable;

}
