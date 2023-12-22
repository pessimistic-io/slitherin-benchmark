// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

import {IICHIVaultFactory} from "./IICHIVaultFactory.sol";
import {IRamsesV2Factory} from "./IRamsesV2Factory.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ICHIVaultDeployer} from "./ICHIVaultDeployer.sol";
import {IRamsesV2Pool} from "./IRamsesV2Pool.sol";
import {IVoter} from "./IVoterV2.sol";

contract ICHIVaultFactory is IICHIVaultFactory, ReentrancyGuard, Ownable {
    
    address constant NULL_ADDRESS = address(0);
    uint256 constant DEFAULT_BASE_FEE = 10**17; // 10%
    uint256 constant DEFAULT_BASE_FEE_SPLIT = 5 * 10**17; // 50%
    uint256 constant PRECISION = 10**18;
    uint32 constant DEFAULT_TWAP_PERIOD = 60 minutes;
    uint16 constant MIN_OBSERVATIONS = 50;
    address public override immutable ramsesV2Factory;
    address public override immutable ramsesV2GaugeFactory;
    address public override feeRecipient;
    uint256 public override baseFee;
    uint256 public override baseFeeSplit;
    uint256 public override veRamTokenId;

    mapping(bytes32 => address) public getICHIVault; 
    address[] public allVaults;

    /**
     @notice creates an instance of ICHIVaultFactory
     @param _ramsesV2Factory Ramses V2 factory
     */
    constructor(address _ramsesV2Factory) {
        require(_ramsesV2Factory != NULL_ADDRESS, 'IVF.constructor: zero address');
        ramsesV2Factory = _ramsesV2Factory;
        ramsesV2GaugeFactory = IVoter(IRamsesV2Factory(_ramsesV2Factory).voter()).clGaugeFactory();
        feeRecipient = msg.sender;
        baseFee = DEFAULT_BASE_FEE; 
        baseFeeSplit = DEFAULT_BASE_FEE_SPLIT;
        veRamTokenId = uint256(-1); 
        emit DeployICHIVaultFactory(msg.sender, _ramsesV2Factory);
    }

    /**
     @notice creates an instance of ICHIVault for specified tokenA/tokenB/fee setting. If needed creates underlying Ramses V2 pool. AllowToken parameters control whether the ICHIVault allows one-sided or two-sided liquidity provision
     @param tokenA tokenA of the Ramses V2 pool
     @param allowTokenA flag that indicates whether tokenA is accepted during deposit
     @param tokenB tokenB of the Ramses V2 pool
     @param allowTokenB flag that indicates whether tokenB is accepted during deposit
     @param fee fee setting of the Ramses V2 pool
     @return ichiVault address of the created ICHIVault
     */
    function createICHIVault(
        address tokenA,
        bool allowTokenA,
        address tokenB,
        bool allowTokenB,
        uint24 fee
    ) external override nonReentrant returns (address ichiVault) {
        require(tokenA != tokenB, 'IVF.createICHIVault: identical tokens');

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (bool allowToken0, bool allowToken1) = tokenA < tokenB ? (allowTokenA, allowTokenB) : (allowTokenB, allowTokenA);

        require(token0 != NULL_ADDRESS, 'IVF.createICHIVault: zero address');
        require(allowTokenA || allowTokenB, 'IVF.createICHIVault: no allowed tokens');

// deployer, token0, token1, fee, allowToken1, allowToken2 -> ichiVault address
        require(getICHIVault[genKey(msg.sender, token0, token1, fee, allowToken0, allowToken1)] == NULL_ADDRESS, 'IVF.createICHIVault: vault exists');

        int24 tickSpacing = IRamsesV2Factory(ramsesV2Factory).feeAmountTickSpacing(fee);
        require(tickSpacing != 0, 'IVF.createICHIVault: fee incorrect');
        address pool = IRamsesV2Factory(ramsesV2Factory).getPool(tokenA, tokenB, fee);
        
        require(pool != NULL_ADDRESS, 'IVF.createICHIVault: pool must exist');

        (/*uint160 sqrtPriceX96*/,
         /*int24 tick*/,
         /*uint16 observationIndex*/,
         /*uint16 observationCardinality*/,
         uint16 observationCardinalityNext,
         /*uint8 feeProtocol*/,
         /*bool unlocked*/
        ) = IRamsesV2Pool(pool).slot0();

        require(observationCardinalityNext >= MIN_OBSERVATIONS, 'IVF.createICHIVault: observation cardinality too low');

        ichiVault = ICHIVaultDeployer.createICHIVault(
                pool, 
                token0,
                allowToken0, 
                token1,
                allowToken1, 
                fee,
                tickSpacing,
                DEFAULT_TWAP_PERIOD,
                allVaults.length
        );

        getICHIVault[genKey(msg.sender, token0, token1, fee, allowToken0, allowToken1)] = ichiVault;
        getICHIVault[genKey(msg.sender, token1, token0, fee, allowToken1, allowToken0)] = ichiVault; // populate mapping in the reverse direction
        allVaults.push(ichiVault);

        emit ICHIVaultCreated(msg.sender, ichiVault, token0, allowToken0, token1, allowToken1, fee, allVaults.length);
    }

    /**
     @notice Sets the fee recipient account address, where portion of the collected swap fees will be distributed
     @dev onlyOwner
     @param _feeRecipient The fee recipient account address
     */
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        require(_feeRecipient != NULL_ADDRESS, 'IVF.setFeeRecipient: zero address');
        feeRecipient = _feeRecipient;
        emit FeeRecipient(msg.sender, _feeRecipient);
    }

    /**
     @notice Sets the fee percentage to be taked from the accumulated pool's swap fees. This percentage is then distributed between the feeRecipient and affiliate accounts
     @dev onlyOwner
     @param _baseFee The fee percentage to be taked from the accumulated pool's swap fee
     */
    function setBaseFee(uint256 _baseFee) external override onlyOwner {
        require(_baseFee <= PRECISION, 'IVF.setBaseFee: must be <= 10**18');
        baseFee = _baseFee;
        emit BaseFee(msg.sender, _baseFee);
    }

    /**
     @notice Sets the fee split ratio between feeRecipient and affilicate accounts. The ratio is set as (baseFeeSplit)/(100 - baseFeeSplit), that is if we want 20/80 ratio (with feeRecipient getting 20%), baseFeeSplit should be set to 20
     @dev onlyOwner
     @param _baseFeeSplit The fee split ratio between feeRecipient and affilicate accounts
     */
    function setBaseFeeSplit(uint256 _baseFeeSplit) external override onlyOwner {
        require(_baseFeeSplit <= PRECISION, 'IVF.setBaseFeeSplit: must be <= 10**18');
        baseFeeSplit = _baseFeeSplit;
        emit BaseFeeSplit(msg.sender, _baseFeeSplit);
    }

    /**
     @notice Sets the veRamTokenId to be used with all furture vaults
     @dev onlyOwner
     @param _veRamTokenId veRamTokenId. When reset, the change does not affect already deployed vaults
     */
    function setVeRamTokenId(uint256 _veRamTokenId) external override onlyOwner {
        veRamTokenId = _veRamTokenId;
        emit VeRamTokenId(msg.sender, _veRamTokenId);
    }

    /**
     * @notice generate a key for getIchiVault
     * @param deployer vault creator
     * @param token0 the first of two tokens in the vault
     * @param token1 the second of two tokens in the vault
     * @param fee the Ramses v2 fee
     * @param allowToken0 allow deposits
     * @param allowToken1 allow deposits
     * @return key generated key
     */
    function genKey(address deployer, address token0, address token1, uint24 fee, bool allowToken0, bool allowToken1) public pure override returns(bytes32 key) {
        key = keccak256(abi.encodePacked(deployer, token0, token1, fee, allowToken0, allowToken1));
    }
}
