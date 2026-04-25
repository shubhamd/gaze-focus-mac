import CoreGraphics
import Foundation

/// Quadratic regression from 2D gaze feature to 2D screen position.
///
/// Model:
///     screen.x = a₀ + a₁·gx + a₂·gy + a₃·gx·gy + a₄·gx² + a₅·gy²
///     screen.y = b₀ + b₁·gx + b₂·gy + b₃·gx·gy + b₄·gx² + b₅·gy²
///
/// 9 calibration points → 9 equations per axis, 6 unknowns each → 3 degrees
/// of redundancy, enough to absorb sample noise without overfitting.
/// Solved via Gaussian elimination on the 6×6 normal equations (A^T A · c = A^T y).
struct GazeMapper {
    let xCoeffs: [Double]   // length 6
    let yCoeffs: [Double]

    static let basisDim = 6
    static let minSamples = 6   // exactly determined; 9 is the recommended count

    static func features(_ gx: Double, _ gy: Double) -> [Double] {
        [1.0, gx, gy, gx * gy, gx * gx, gy * gy]
    }

    func map(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint {
        let f = Self.features(Double(gx), Double(gy))
        var x = 0.0, y = 0.0
        for i in 0..<Self.basisDim {
            x += f[i] * xCoeffs[i]
            y += f[i] * yCoeffs[i]
        }
        return CGPoint(x: x, y: y)
    }

    /// Fit from (gaze, screen) pairs. Returns nil on too-few-samples or
    /// singular normal matrix (collinear calibration points).
    static func fit(samples: [(gaze: CGPoint, screen: CGPoint)]) -> GazeMapper? {
        guard samples.count >= minSamples else { return nil }

        // M = AᵀA (6×6); rx = Aᵀ·screen_x, ry = Aᵀ·screen_y (6-vec each).
        var M = Array(repeating: Array(repeating: 0.0, count: basisDim), count: basisDim)
        var rx = Array(repeating: 0.0, count: basisDim)
        var ry = Array(repeating: 0.0, count: basisDim)

        for s in samples {
            let f = features(Double(s.gaze.x), Double(s.gaze.y))
            let sx = Double(s.screen.x), sy = Double(s.screen.y)
            for i in 0..<basisDim {
                rx[i] += f[i] * sx
                ry[i] += f[i] * sy
                for j in 0..<basisDim {
                    M[i][j] += f[i] * f[j]
                }
            }
        }

        guard let xC = solve(M, rx),
              let yC = solve(M, ry) else { return nil }
        return GazeMapper(xCoeffs: xC, yCoeffs: yC)
    }

    /// Gauss-Jordan with partial pivoting. Mutates copies of M and b.
    /// Returns nil if any pivot is < 1e-12 (effectively singular).
    private static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = matrix.count
        var A = matrix
        var b = vector

        for k in 0..<n {
            var pivotRow = k
            var pivotMag = abs(A[k][k])
            for i in (k + 1)..<n where abs(A[i][k]) > pivotMag {
                pivotRow = i
                pivotMag = abs(A[i][k])
            }
            if pivotMag < 1e-12 { return nil }
            if pivotRow != k {
                A.swapAt(k, pivotRow)
                b.swapAt(k, pivotRow)
            }
            for i in 0..<n where i != k {
                let factor = A[i][k] / A[k][k]
                if factor == 0 { continue }
                for j in k..<n {
                    A[i][j] -= factor * A[k][j]
                }
                b[i] -= factor * b[k]
            }
        }

        var x = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            x[i] = b[i] / A[i][i]
        }
        return x
    }
}
