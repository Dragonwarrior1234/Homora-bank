pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/ERC1155.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/math/SafeMath.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/utils/ReentrancyGuard.sol';

import '../../interfaces/IERC20Wrapper.sol';
import '../../interfaces/IMasterChef.sol';

contract WMasterChef is ERC1155('WMasterChef'), ReentrancyGuard, IERC20Wrapper {
  using SafeMath for uint;
  using SafeERC20 for IERC20;

  IMasterChef public chef;
  IERC20 public sushi;

  constructor(IMasterChef _chef) public {
    chef = _chef;
    sushi = IERC20(_chef.sushi());
  }

  function encodeId(uint pid, uint sushiPerShare) public pure returns (uint id) {
    require(pid < (1 << 16), 'bad pid');
    require(sushiPerShare < (1 << 240), 'bad sushi per share');
    return (id << 240) | sushiPerShare;
  }

  function decodeId(uint id) public pure returns (uint pid, uint sushiPerShare) {
    pid = id >> 240; // First 16 bits
    sushiPerShare = id & ((1 << 240) - 1); // Last 240 bits
  }

  /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
  function getUnderlying(uint id) external view override returns (address) {
    (uint pid, ) = decodeId(id);
    (address lpToken, , , ) = chef.poolInfo(pid);
    return lpToken;
  }

  /// @dev Mint ERC1155 token for the given pool id.
  /// @return id The token id that got minted.
  function mint(uint pid, uint amount) external nonReentrant returns (uint) {
    (address lpToken, , , ) = chef.poolInfo(pid);
    IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
    if (IERC20(lpToken).allowance(address(this), address(chef)) != uint(-1)) {
      // We only need to this once per pool id, as LP token's allowance won't decrease if it's -1.
      IERC20(lpToken).approve(address(chef), uint(-1));
    }
    chef.deposit(pid, amount);
    (, , , uint sushiPerShare) = chef.poolInfo(pid);
    uint id = encodeId(pid, sushiPerShare);
    _mint(msg.sender, id, amount, '');
    return id;
  }

  /// @dev Burn ERC1155 token to redeem LP ERC20 token back.
  /// @return pid The pool id that that you received LP token back.
  function burn(uint id, uint amount) external nonReentrant returns (uint) {
    (uint pid, uint stSushiPerShare) = decodeId(id);
    _burn(msg.sender, id, amount);
    chef.withdraw(pid, amount);
    (address lpToken, , , uint enSushiPerShare) = chef.poolInfo(pid);
    IERC20(lpToken).safeTransfer(msg.sender, amount);
    sushi.safeTransfer(msg.sender, amount.mul(enSushiPerShare.sub(stSushiPerShare)).div(1e12));
    return pid;
  }
}
