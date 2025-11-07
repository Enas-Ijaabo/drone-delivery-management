package iface

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/Enas-Ijaabo/drone-delivery-management/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const (
	CtxUserID      = "user_id"
	CtxJWTUserName = "jwt_user_name"
	CtxJWTUserRole = "jwt_user_role"

	headerAuthorization   = "Authorization"
	headerWWWAuthenticate = "WWW-Authenticate"
	bearerScheme          = "Bearer"

	jsonKeyError   = "error"
	jsonKeyMessage = "message"
	jsonErrUnauth  = "unauthorized"
	jsonErrForbid  = "forbidden"

	msgMissingInvalidBearer = "missing/invalid bearer token"
	msgExpiredToken         = "expired token"
	msgNotYetValid          = "token not yet valid"
	msgInvalidToken         = "invalid token"
	msgInvalidIssuer        = "invalid token issuer"
	msgInvalidAudience      = "invalid token audience"
	msgMissingExp           = "missing exp"
	msgMissingClaims        = "missing required claims"
	msgMissingAuth          = "missing authentication"
	msgInvalidRole          = "invalid role"
	msgRoleNotAllowed       = "role not allowed"

	wwwAuthPrefix = "Bearer error=\"invalid_token\", error_description=\""
	wwwAuthSuffix = "\""
)

type Claims struct {
	Name string `json:"name,omitempty"`
	Role string `json:"role,omitempty"`
	jwt.RegisteredClaims
}

// AuthMiddleware validates HS256 JWT and sets jwt_* identity in context.
func AuthMiddleware(secret []byte, issuer string, audience string) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenStr, ok := extractBearerToken(c.GetHeader(headerAuthorization))
		if !ok {
			unauth(c, msgMissingInvalidBearer)
			return
		}

		opts := []jwt.ParserOption{
			jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
			jwt.WithLeeway(30 * time.Second),
		}
		if issuer != "" {
			opts = append(opts, jwt.WithIssuer(issuer))
		}
		if audience != "" {
			opts = append(opts, jwt.WithAudience(audience))
		}
		parser := jwt.NewParser(opts...)

		claims := &Claims{}
		tok, err := parser.ParseWithClaims(tokenStr, claims, func(token *jwt.Token) (interface{}, error) {
			return secret, nil
		})
		if err != nil {
			switch {
			case errors.Is(err, jwt.ErrTokenExpired):
				unauth(c, msgExpiredToken)
			case errors.Is(err, jwt.ErrTokenNotValidYet):
				unauth(c, msgNotYetValid)
			default:
				unauth(c, msgInvalidToken)
			}
			return
		}
		if tok == nil || !tok.Valid {
			unauth(c, msgInvalidToken)
			return
		}

		if issuer != "" && claims.Issuer != issuer {
			unauth(c, msgInvalidIssuer)
			return
		}
		if audience != "" {
			audOK := false
			for _, a := range claims.Audience {
				if a == audience {
					audOK = true
					break
				}
			}
			if !audOK {
				unauth(c, msgInvalidAudience)
				return
			}
		}

		if claims.ExpiresAt == nil {
			unauth(c, msgMissingExp)
			return
		}
		if claims.Subject == "" || claims.Name == "" || claims.Role == "" {
			unauth(c, msgMissingClaims)
			return
		}

		c.Set(CtxUserID, claims.Subject)
		c.Set(CtxJWTUserName, claims.Name)
		c.Set(CtxJWTUserRole, claims.Role)

		c.Next()
	}
}

func extractBearerToken(h string) (string, bool) {
	parts := strings.SplitN(h, " ", 2)
	if h == "" || len(parts) != 2 || !strings.EqualFold(parts[0], bearerScheme) {
		return "", false
	}
	tok := strings.TrimSpace(parts[1])
	if tok == "" {
		return "", false
	}
	return tok, true
}

func unauth(c *gin.Context, msg string) {
	c.Header(headerWWWAuthenticate, wwwAuthPrefix+msg+wwwAuthSuffix)
	c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{jsonKeyError: jsonErrUnauth, jsonKeyMessage: msg})
}

// RequireRoles checks that the authenticated user's role is in the allowed list.
// Must be used after AuthMiddleware.
func RequireRoles(allowed ...model.Role) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get(CtxJWTUserRole)
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{jsonKeyError: jsonErrForbid, jsonKeyMessage: msgMissingAuth})
			return
		}
		roleStr, ok := role.(string)
		if !ok || roleStr == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{jsonKeyError: jsonErrForbid, jsonKeyMessage: msgInvalidRole})
			return
		}
		for _, r := range allowed {
			if string(r) == roleStr {
				c.Next()
				return
			}
		}
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{jsonKeyError: jsonErrForbid, jsonKeyMessage: msgRoleNotAllowed})
	}
}
