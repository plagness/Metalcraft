import simd

/// Fast simplex noise implementation using simd for terrain generation.
struct SimplexNoise {

    let seed: Int
    private let perm: [Int]
    private let grad3: [SIMD3<Float>] = [
        SIMD3<Float>( 1, 1, 0), SIMD3<Float>(-1, 1, 0), SIMD3<Float>( 1,-1, 0), SIMD3<Float>(-1,-1, 0),
        SIMD3<Float>( 1, 0, 1), SIMD3<Float>(-1, 0, 1), SIMD3<Float>( 1, 0,-1), SIMD3<Float>(-1, 0,-1),
        SIMD3<Float>( 0, 1, 1), SIMD3<Float>( 0,-1, 1), SIMD3<Float>( 0, 1,-1), SIMD3<Float>( 0,-1,-1),
    ]

    init(seed: Int = 42) {
        self.seed = seed
        // Generate permutation table from seed
        var p = Array(0..<256)
        var rng = seed
        for i in stride(from: 255, through: 1, by: -1) {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let j = abs(rng) % (i + 1)
            p.swapAt(i, j)
        }
        self.perm = p + p // Double it to avoid wrapping
    }

    // MARK: - 2D Simplex Noise

    func noise2D(x: Float, y: Float) -> Float {
        let F2: Float = 0.5 * (sqrt(3.0) - 1.0)
        let G2: Float = (3.0 - sqrt(3.0)) / 6.0

        let s = (x + y) * F2
        let i = fastFloor(x + s)
        let j = fastFloor(y + s)
        let t = Float(i + j) * G2

        let X0 = Float(i) - t
        let Y0 = Float(j) - t
        let x0 = x - X0
        let y0 = y - Y0

        let i1: Int, j1: Int
        if x0 > y0 { i1 = 1; j1 = 0 }
        else { i1 = 0; j1 = 1 }

        let x1 = x0 - Float(i1) + G2
        let y1 = y0 - Float(j1) + G2
        let x2 = x0 - 1.0 + 2.0 * G2
        let y2 = y0 - 1.0 + 2.0 * G2

        let ii = i & 255
        let jj = j & 255

        var n0: Float = 0, n1: Float = 0, n2: Float = 0

        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 >= 0 {
            t0 *= t0
            let gi = perm[ii + perm[jj]] % 12
            n0 = t0 * t0 * dot2(grad3[gi], x0, y0)
        }

        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 >= 0 {
            t1 *= t1
            let gi = perm[ii + i1 + perm[jj + j1]] % 12
            n1 = t1 * t1 * dot2(grad3[gi], x1, y1)
        }

        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 >= 0 {
            t2 *= t2
            let gi = perm[ii + 1 + perm[jj + 1]] % 12
            n2 = t2 * t2 * dot2(grad3[gi], x2, y2)
        }

        return 70.0 * (n0 + n1 + n2) // Range: [-1, 1]
    }

    // MARK: - 3D Simplex Noise

    func noise3D(x: Float, y: Float, z: Float) -> Float {
        let F3: Float = 1.0 / 3.0
        let G3: Float = 1.0 / 6.0

        let s = (x + y + z) * F3
        let i = fastFloor(x + s)
        let j = fastFloor(y + s)
        let k = fastFloor(z + s)
        let t = Float(i + j + k) * G3

        let X0 = Float(i) - t
        let Y0 = Float(j) - t
        let Z0 = Float(k) - t
        let x0 = x - X0, y0 = y - Y0, z0 = z - Z0

        let (i1, j1, k1, i2, j2, k2): (Int, Int, Int, Int, Int, Int)
        if x0 >= y0 {
            if y0 >= z0      { (i1,j1,k1,i2,j2,k2) = (1,0,0,1,1,0) }
            else if x0 >= z0 { (i1,j1,k1,i2,j2,k2) = (1,0,0,1,0,1) }
            else              { (i1,j1,k1,i2,j2,k2) = (0,0,1,1,0,1) }
        } else {
            if y0 < z0       { (i1,j1,k1,i2,j2,k2) = (0,0,1,0,1,1) }
            else if x0 < z0  { (i1,j1,k1,i2,j2,k2) = (0,1,0,0,1,1) }
            else              { (i1,j1,k1,i2,j2,k2) = (0,1,0,1,1,0) }
        }

        let x1 = x0 - Float(i1) + G3, y1 = y0 - Float(j1) + G3, z1 = z0 - Float(k1) + G3
        let x2 = x0 - Float(i2) + 2*G3, y2 = y0 - Float(j2) + 2*G3, z2 = z0 - Float(k2) + 2*G3
        let x3 = x0 - 1 + 3*G3, y3 = y0 - 1 + 3*G3, z3 = z0 - 1 + 3*G3

        let ii = i & 255, jj = j & 255, kk = k & 255
        var n0: Float = 0, n1: Float = 0, n2: Float = 0, n3: Float = 0

        var t0 = 0.6 - x0*x0 - y0*y0 - z0*z0
        if t0 >= 0 { t0 *= t0; n0 = t0 * t0 * simd_dot(grad3[perm[ii+perm[jj+perm[kk]]] % 12], SIMD3(x0,y0,z0)) }
        var t1 = 0.6 - x1*x1 - y1*y1 - z1*z1
        if t1 >= 0 { t1 *= t1; n1 = t1 * t1 * simd_dot(grad3[perm[ii+i1+perm[jj+j1+perm[kk+k1]]] % 12], SIMD3(x1,y1,z1)) }
        var t2 = 0.6 - x2*x2 - y2*y2 - z2*z2
        if t2 >= 0 { t2 *= t2; n2 = t2 * t2 * simd_dot(grad3[perm[ii+i2+perm[jj+j2+perm[kk+k2]]] % 12], SIMD3(x2,y2,z2)) }
        var t3 = 0.6 - x3*x3 - y3*y3 - z3*z3
        if t3 >= 0 { t3 *= t3; n3 = t3 * t3 * simd_dot(grad3[perm[ii+1+perm[jj+1+perm[kk+1]]] % 12], SIMD3(x3,y3,z3)) }

        return 32.0 * (n0 + n1 + n2 + n3)
    }

    // MARK: - Fractal Brownian Motion

    func fbm2D(x: Float, y: Float, octaves: Int = 6, lacunarity: Float = 2.0, persistence: Float = 0.5) -> Float {
        var value: Float = 0
        var amplitude: Float = 1
        var frequency: Float = 1
        var maxAmplitude: Float = 0

        for _ in 0..<octaves {
            value += noise2D(x: x * frequency, y: y * frequency) * amplitude
            maxAmplitude += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }
        return value / maxAmplitude
    }

    func fbm3D(x: Float, y: Float, z: Float, octaves: Int = 4, lacunarity: Float = 2.0, persistence: Float = 0.5) -> Float {
        var value: Float = 0
        var amplitude: Float = 1
        var frequency: Float = 1
        var maxAmplitude: Float = 0

        for _ in 0..<octaves {
            value += noise3D(x: x * frequency, y: y * frequency, z: z * frequency) * amplitude
            maxAmplitude += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }
        return value / maxAmplitude
    }

    // MARK: - Helpers

    @inline(__always)
    private func fastFloor(_ x: Float) -> Int {
        let xi = Int(x)
        return x < Float(xi) ? xi - 1 : xi
    }

    @inline(__always)
    private func dot2(_ g: SIMD3<Float>, _ x: Float, _ y: Float) -> Float {
        return g.x * x + g.y * y
    }
}
