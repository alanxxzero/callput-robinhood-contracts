// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC165 } from './IERC165.sol';
import { IERC165BaseInternal } from './IERC165BaseInternal.sol';

interface IERC165Base is IERC165, IERC165BaseInternal {}
