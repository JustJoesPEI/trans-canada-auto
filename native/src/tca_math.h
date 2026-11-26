#pragma once

// GDScript's own arithmetic, exactly, for the native twins of GDScript code
// (native/README.md). GDScript's `float` is a 64-bit double; Vector2 is
// 32-bit floats, and a double meeting a Vector2 (v * x, v / x) is made a
// float first. The engine's Vector2 helpers are written out here as the
// engine has them (godot-cpp's copies differ at the edges: normalizing a
// vector that isn't finite).

#include <cmath>
#include <cstdint>

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace tca {

using godot::Vector2;

// The engine's SIGN: NAN is 0.
static inline double signf(double x) { return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0); }
static inline double minf(double a, double b) { return a < b ? a : b; }
static inline double maxf(double a, double b) { return a > b ? a : b; }
static inline int64_t mini(int64_t a, int64_t b) { return a < b ? a : b; }
static inline int64_t maxi(int64_t a, int64_t b) { return a > b ? a : b; }
static inline double clampf(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }
static inline int64_t clampi(int64_t x, int64_t lo, int64_t hi) { return x < lo ? lo : (x > hi ? hi : x); }
static inline double absf(double x) { return std::fabs(x); }
static inline double lerpf(double a, double b, double w) { return a + (b - a) * w; }
static inline double move_toward(double from, double to, double delta) {
	return std::fabs(to - from) <= delta ? to : from + signf(to - from) * delta;
}
// GDScript int(x) of a float.
static inline int64_t to_int(double x) { return (int64_t)x; }

// Vector2, as the engine does it (core/math/vector2.cpp, 4.7).
static inline float len(const Vector2 &v) { return std::sqrt(v.x * v.x + v.y * v.y); }
static inline float len2(const Vector2 &v) { return v.x * v.x + v.y * v.y; }
static inline float dot(const Vector2 &a, const Vector2 &b) { return a.x * b.x + a.y * b.y; }
static inline float cross(const Vector2 &a, const Vector2 &b) { return a.x * b.y - a.y * b.x; }
static inline float dist(const Vector2 &a, const Vector2 &b) {
	return std::sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}
static inline float dist2(const Vector2 &a, const Vector2 &b) {
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);
}
static inline Vector2 nrm(const Vector2 &v) {
	if (!std::isfinite(v.x) || !std::isfinite(v.y)) {
		return Vector2();
	}
	float l = v.x * v.x + v.y * v.y;
	if (l == 0.0f) {
		return Vector2();
	}
	l = std::sqrt(l);
	return Vector2(v.x / l, v.y / l);
}
static inline Vector2 lerp2(const Vector2 &a, const Vector2 &b, float w) {
	return Vector2(a.x + (b.x - a.x) * w, a.y + (b.y - a.y) * w);
}
static inline float angle_to(const Vector2 &a, const Vector2 &b) { return std::atan2(cross(a, b), dot(a, b)); }
// Geometry2D.get_closest_point_to_segment.
static inline Vector2 closest_on_segment(const Vector2 &p, const Vector2 &a, const Vector2 &b) {
	Vector2 pp = p - a;
	Vector2 n = b - a;
	float l2 = len2(n);
	if (l2 < 1e-20f) {
		return a;
	}
	float d = dot(n, pp) / l2;
	if (d <= 0.0f) {
		return a;
	} else if (d >= 1.0f) {
		return b;
	}
	return a + n * d;
}

// Array.sort_custom's sort (core/templates/sort_array.h, 4.7), so equal
// keys come out in the same order as GDScript's.
template <typename T, typename Less>
struct Sorter {
	Less compare;
	static const int64_t THRESHOLD = 16;

	int64_t median_of_3_index(const T *p, int64_t ai, int64_t bi, int64_t ci) const {
		const T &a = p[ai];
		const T &b = p[bi];
		const T &c = p[ci];
		if (compare(a, b)) {
			if (compare(b, c)) {
				return bi;
			} else if (compare(a, c)) {
				return ci;
			}
			return ai;
		} else if (compare(a, c)) {
			return ai;
		} else if (compare(b, c)) {
			return ci;
		}
		return bi;
	}
	static int64_t bitlog(int64_t n) {
		int64_t k;
		for (k = 0; n != 1; n >>= 1) {
			++k;
		}
		return k;
	}
	void push_heap(int64_t first, int64_t hole, int64_t top, T value, T *a) const {
		int64_t parent = (hole - 1) / 2;
		while (hole > top && compare(a[first + parent], value)) {
			a[first + hole] = a[first + parent];
			hole = parent;
			parent = (hole - 1) / 2;
		}
		a[first + hole] = value;
	}
	void adjust_heap(int64_t first, int64_t hole, int64_t len, T value, T *a) const {
		int64_t top = hole;
		int64_t second = 2 * hole + 2;
		while (second < len) {
			if (compare(a[first + second], a[first + (second - 1)])) {
				second--;
			}
			a[first + hole] = a[first + second];
			hole = second;
			second = 2 * (second + 1);
		}
		if (second == len) {
			a[first + hole] = a[first + (second - 1)];
			hole = second - 1;
		}
		push_heap(first, hole, top, value, a);
	}
	void pop_heap(int64_t first, int64_t last, int64_t result, T value, T *a) const {
		a[result] = a[first];
		adjust_heap(first, 0, last - first, value, a);
	}
	void pop_heap(int64_t first, int64_t last, T *a) const {
		pop_heap(first, last - 1, last - 1, a[last - 1], a);
	}
	void sort_heap(int64_t first, int64_t last, T *a) const {
		while (last - first > 1) {
			pop_heap(first, last--, a);
		}
	}
	void make_heap(int64_t first, int64_t last, T *a) const {
		if (last - first < 2) {
			return;
		}
		int64_t len = last - first;
		int64_t parent = (len - 2) / 2;
		while (true) {
			adjust_heap(first, parent, len, a[first + parent], a);
			if (parent == 0) {
				return;
			}
			parent--;
		}
	}
	void partial_sort(int64_t first, int64_t last, int64_t middle, T *a) const {
		make_heap(first, middle, a);
		for (int64_t i = middle; i < last; i++) {
			if (compare(a[i], a[first])) {
				pop_heap(first, middle, i, a[i], a);
			}
		}
		sort_heap(first, middle, a);
	}
	int64_t partitioner(int64_t first, int64_t last, int64_t pivot, T *a) const {
		const T *pv = &a[pivot];
		while (true) {
			while (first != pivot && compare(a[first], *pv)) {
				first++;
			}
			last--;
			while (last != pivot && compare(*pv, a[last])) {
				last--;
			}
			if (first >= last) {
				return first;
			}
			if (pv == &a[first]) {
				pv = &a[last];
			} else if (pv == &a[last]) {
				pv = &a[first];
			}
			T tmp = a[first];
			a[first] = a[last];
			a[last] = tmp;
			first++;
		}
	}
	void introsort(int64_t first, int64_t last, T *a, int64_t depth) const {
		while (last - first > THRESHOLD) {
			if (depth == 0) {
				partial_sort(first, last, last, a);
				return;
			}
			depth--;
			int64_t cut = partitioner(first, last, median_of_3_index(a, first, first + (last - first) / 2, last - 1), a);
			introsort(cut, last, a, depth);
			last = cut;
		}
	}
	void unguarded_linear_insert(int64_t last, T value, T *a) const {
		int64_t next = last - 1;
		while (compare(value, a[next])) {
			a[last] = a[next];
			last = next;
			next--;
		}
		a[last] = value;
	}
	void linear_insert(int64_t first, int64_t last, T *a) const {
		T val = a[last];
		if (compare(val, a[first])) {
			for (int64_t i = last; i > first; i--) {
				a[i] = a[i - 1];
			}
			a[first] = val;
		} else {
			unguarded_linear_insert(last, val, a);
		}
	}
	void insertion_sort(int64_t first, int64_t last, T *a) const {
		if (first == last) {
			return;
		}
		for (int64_t i = first + 1; i != last; i++) {
			linear_insert(first, i, a);
		}
	}
	void unguarded_insertion_sort(int64_t first, int64_t last, T *a) const {
		for (int64_t i = first; i != last; i++) {
			unguarded_linear_insert(i, a[i], a);
		}
	}
	void sort(T *a, int64_t n) const {
		if (n == 0) {
			return;
		}
		introsort(0, n, a, bitlog(n) * 2);
		if (n > THRESHOLD) {
			insertion_sort(0, THRESHOLD, a);
			unguarded_insertion_sort(THRESHOLD, n, a);
		} else {
			insertion_sort(0, n, a);
		}
	}
};

} // namespace tca
