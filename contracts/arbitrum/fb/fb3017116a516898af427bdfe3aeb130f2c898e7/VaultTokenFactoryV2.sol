pragma solidity =0.5.16;

import "./Ownable.sol";
import "./VaultTokenV2.sol";
import "./IMasterChef.sol";
import "./IVaultTokenFactoryV2.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";

contract VaultTokenFactoryV2 is Ownable, IVaultTokenFactoryV2 {
    address public optiSwap;
    address public router;
    address public masterChef;
    address public rewardsToken;
    address public reinvestFeeTo;

    mapping(uint256 => address) public getVaultToken;
    address[] public allVaultTokens;

    event VaultTokenCreated(
        uint256 indexed pid,
        address vaultToken,
        uint256 vaultTokenIndex
    );

    constructor(
        address _optiSwap,
        address _router,
        address _masterChef,
        address _rewardsToken,
        address _reinvestFeeTo
    ) public {
        optiSwap = _optiSwap;
        router = _router;
        masterChef = _masterChef;
        rewardsToken = _rewardsToken;
        reinvestFeeTo = _reinvestFeeTo;
    }

    function allVaultTokensLength() external view returns (uint256) {
        return allVaultTokens.length;
    }

    function createVaultToken(uint256 pid)
        external
        returns (address vaultToken)
    {
        require(
            getVaultToken[pid] == address(0),
            "VaultTokenFactory: PID_EXISTS"
        );
        bytes memory bytecode = type(VaultTokenV2).creationCode;
        assembly {
            vaultToken := create2(0, add(bytecode, 32), mload(bytecode), pid)
        }
        VaultTokenV2(vaultToken)._initialize(
            optiSwap,
            IUniswapV2Router01(router),
            IMasterChef(masterChef),
            rewardsToken,
            pid,
            reinvestFeeTo
        );
        getVaultToken[pid] = vaultToken;
        allVaultTokens.push(vaultToken);
        emit VaultTokenCreated(pid, vaultToken, allVaultTokens.length);
    }
}

