// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    UpgradeableBeacon
} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    BeaconProxy
} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {RebalancerVaultUpgradeable} from "../RebalancerVaultUpgradeable.sol";
import {IRebalancerVault} from "../interfaces/IRebalancerVault.sol";

contract VaultFactory is UpgradeableBeacon {
    using SafeERC20 for IERC20;

    address public immutable positionManager;
    address public immutable swapRouter;
    address public immutable dexAdapter;

    address public guardian;
    mapping(address => mapping(address => address)) public vaultFor;
    address[] public allVaults;

    event VaultDeployed(
        address indexed vault,
        address indexed pool,
        address indexed strategy,
        address owner,
        address operator
    );
    event VaultSeeded(
        address indexed vault,
        address indexed seeder,
        uint256 seedAssets,
        uint256 tokenId
    );
    event GuardianUpdated(address indexed newGuardian);
    event PausedAll(uint256 count);

    error NotGuardian();
    error ZeroAddress();
    error VaultExists();

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(
        address implementation,
        address _positionManager,
        address _swapRouter,
        address _dexAdapter,
        address _guardian,
        address _owner
    ) UpgradeableBeacon(implementation, _owner) {
        if (
            _positionManager == address(0) ||
            _swapRouter == address(0) ||
            _dexAdapter == address(0) ||
            _guardian == address(0)
        ) revert ZeroAddress();

        positionManager = _positionManager;
        swapRouter = _swapRouter;
        dexAdapter = _dexAdapter;
        guardian = _guardian;
    }

    function deployVault(
        address pool,
        address strategy,
        address vaultOwner,
        address operator,
        address feeRecipient,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address vault) {
        return
            _deploy(
                pool,
                strategy,
                vaultOwner,
                operator,
                feeRecipient,
                name,
                symbol
            );
    }

    function deploySeedAndInitialize(
        address pool,
        address strategy,
        address vaultOwner,
        address operator,
        address feeRecipient,
        string memory name,
        string memory symbol,
        uint256 seedAssets,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Min,
        uint256 amount1Min
    ) external onlyOwner returns (address vault) {
        if (vaultOwner == address(0)) revert ZeroAddress();

        vault = _deploy(
            pool,
            strategy,
            address(this),
            operator,
            feeRecipient,
            name,
            symbol
        );

        RebalancerVaultUpgradeable v = RebalancerVaultUpgradeable(
            payable(vault)
        );
        address token0 = address(v.token0());
        address token1 = address(v.token1());

        IERC20(token0).safeTransferFrom(msg.sender, address(this), seedAssets);
        IERC20(token0).forceApprove(vault, seedAssets);
        v.deposit(seedAssets, msg.sender);

        v.initializePosition(
            tickLower,
            tickUpper,
            IERC20(token0).balanceOf(vault),
            IERC20(token1).balanceOf(vault),
            amount0Min,
            amount1Min
        );

        v.transferOwnership(vaultOwner);

        emit VaultSeeded(vault, msg.sender, seedAssets, v.tokenId());
    }

    function pauseAll() external onlyGuardian {
        uint256 n = allVaults.length;
        for (uint256 i; i < n; i++) {
            IRebalancerVault(allVaults[i]).pauseByGuardian();
        }
        emit PausedAll(n);
    }

    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        guardian = newGuardian;
        emit GuardianUpdated(newGuardian);
    }

    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    function _deploy(
        address pool,
        address strategy,
        address vaultOwner,
        address operator,
        address feeRecipient,
        string memory name,
        string memory symbol
    ) internal returns (address vault) {
        if (vaultFor[pool][strategy] != address(0)) revert VaultExists();

        bytes memory initData = abi.encodeCall(
            RebalancerVaultUpgradeable.initialize,
            (
                RebalancerVaultUpgradeable.InitParams({
                    owner: vaultOwner,
                    operator: operator,
                    guardian: address(this),
                    pool: pool,
                    positionManager: positionManager,
                    swapRouter: swapRouter,
                    strategy: strategy,
                    dexAdapter: dexAdapter,
                    feeRecipient: feeRecipient,
                    name: name,
                    symbol: symbol
                })
            )
        );

        vault = address(new BeaconProxy(address(this), initData));

        vaultFor[pool][strategy] = vault;
        allVaults.push(vault);

        emit VaultDeployed(vault, pool, strategy, vaultOwner, operator);
    }
}
